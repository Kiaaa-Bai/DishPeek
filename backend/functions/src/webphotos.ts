// A photo from the web for the dishes Wikipedia has no picture of (2026-11-19).
//
// 1. Shared cache: any dish someone already scanned keeps the photo found for it, for everyone.
//    Most dishes on most menus repeat, so the search below runs less and less over time.
// 2. Brave image search with the dish's name as printed on the menu (만둣국, not "dumpling soup"),
//    which finds photos people took of that dish where it is from.
// 3. Gemini looks at the first few results of every dish in one request and picks the one that
//    shows the dish itself, served, not a shop sign, a logo or a different dish.
//
// Cost, per new dish: one Brave search (about $0.005) plus its share of the Gemini request
// (about $0.0005 for 4 small images). Dishes found in the cache cost nothing.
// Only the photo's address is kept, not the photo, so there is nothing to store or serve.

import * as logger from "firebase-functions/logger";
import type { Firestore } from "firebase-admin/firestore";
import { vertexAI } from "./vertex";
import { MENU_MODEL } from "./menu";
import type { DishPicture, DishQuery, PhotoFinder } from "./photos";

const CANDIDATES = 4; // photos per dish that Gemini chooses from
const MAX_SEARCHES = 30; // per request, so one huge menu can't run up the bill
const NO_PHOTO_DAYS = 30; // a dish with no good photo is searched again after this long
const DISHES_PER_PICK = 5; // Gemini requests run side by side, a few dishes each, instead of one big one

// Speed (2026-11-19): the first version took about 45 s for a 19-dish menu, because it searched 3 dishes
// at a time, fetched thumbnails and checked photos one dish after another, and sent ~95 photos to
// Gemini in one request. Brave allows 50 searches a second, so now every step runs at once.

type Candidate = { image: string; thumbnail: string; page: string };

// search false: only the shared cache, which answers in a moment (the app's first, quick request).
export function webPhotos(db: Firestore, braveKey: string, search = true): PhotoFinder {
  return {
    name: search ? "web" : "web cache",
    async find(dishes) {
      const found: Record<string, DishPicture> = {};

      // 1. The shared cache.
      const refs = dishes.map((dish) => db.collection("dishPhotoCache").doc(cacheId(dish)));
      const cached = refs.length > 0 ? await db.getAll(...refs) : [];
      const toSearch: DishQuery[] = [];
      dishes.forEach((dish, index) => {
        const entry = cached[index]?.data();
        if (entry?.url) {
          found[dish.id] = { url: entry.url, credit: "", link: entry.link ?? "", source: "web" };
        } else if (entry?.none && Date.now() - entry.at < NO_PHOTO_DAYS * 86_400_000) {
          // Searched recently and nothing fit: don't pay for the same search again yet.
        } else {
          toSearch.push(dish);
        }
      });
      if (toSearch.length === 0 || !search) return found;

      const started = Date.now();
      // 2. Brave, every dish at once.
      const searching = toSearch.slice(0, MAX_SEARCHES);
      const candidates = new Map<string, Candidate[]>();
      await Promise.all(searching.map(async (dish) => {
        candidates.set(dish.id, await searchBrave(dish, braveKey));
      }));
      const searched = Date.now();

      // 3. Gemini picks, a few dishes per request, all requests at once.
      const groups: DishQuery[][] = [];
      for (let i = 0; i < searching.length; i += DISHES_PER_PICK) groups.push(searching.slice(i, i + DISHES_PER_PICK));
      const picks = new Map<string, Candidate>();
      await Promise.all(groups.map(async (group) => {
        try {
          for (const [id, choice] of await pickPhotos(group, candidates)) picks.set(id, choice);
        } catch (error) {
          // One group failing costs only its own dishes.
          logger.warn("photo pick failed", { error: String(error) });
        }
      }));
      const picked = Date.now();

      // Keep what was found, and remember the dishes where nothing fit.
      const urls = await Promise.all(searching.map(async (dish) => {
        const choice = picks.get(dish.id);
        if (!choice) return undefined;
        return (await reachable(choice.image)) ? choice.image : choice.thumbnail;
      }));
      const batch = db.batch();
      searching.forEach((dish, index) => {
        const choice = picks.get(dish.id);
        const url = urls[index];
        const ref = db.collection("dishPhotoCache").doc(cacheId(dish));
        if (choice && url) {
          found[dish.id] = { url, credit: "", link: choice.page, source: "web" };
          batch.set(ref, { url, link: choice.page, name: dish.originalName, at: Date.now() });
        } else {
          batch.set(ref, { none: true, name: dish.originalName, at: Date.now() });
        }
      });
      await batch.commit();
      logger.info("webPhotos", {
        cached: dishes.length - toSearch.length, searched: searching.length, found: picks.size,
        searchMs: searched - started, pickMs: picked - searched, totalMs: Date.now() - started,
      });
      return found;
    },
  };
}

// The same dish on any menu shares one entry; "-2" marks a second dish with the same name on one menu.
function cacheId(dish: DishQuery): string {
  return dish.id.replace(/(-2)+$/, "") || "dish";
}

async function searchBrave(dish: DishQuery, key: string): Promise<Candidate[]> {
  const url = new URL("https://api.search.brave.com/res/v1/images/search");
  url.search = new URLSearchParams({ q: dish.originalName, count: String(CANDIDATES), safesearch: "strict" }).toString();
  try {
    const response = await fetch(url, { headers: { Accept: "application/json", "X-Subscription-Token": key } });
    if (!response.ok) {
      logger.warn("Brave image search failed", { status: response.status, dish: dish.originalName });
      return [];
    }
    const body: any = await response.json();
    return (body.results ?? [])
      .map((r: any) => ({ image: r.properties?.url ?? "", thumbnail: r.thumbnail?.src ?? "", page: r.url ?? "" }))
      .filter((c: Candidate) => c.image && c.thumbnail)
      .slice(0, CANDIDATES);
  } catch (error) {
    logger.warn("Brave image search failed", { dish: dish.originalName, error: String(error) });
    return [];
  }
}

// Gemini sees each dish's candidates (Brave's small thumbnails) and names the one that shows the dish.
async function pickPhotos(dishes: DishQuery[], candidates: Map<string, Candidate[]>): Promise<Map<string, Candidate>> {
  const parts: any[] = [{
    text: `For each numbered dish from a restaurant menu, pick the photo that shows that dish as it is served.
Pick -1 when none does: a shop sign, logo, menu, packaging, person, raw ingredient or a different dish is not the dish.
Prefer a clear, appetizing photo of a single serving.`,
  }];
  const asked: Array<{ dish: DishQuery; options: Candidate[] }> = [];
  // Every thumbnail of every dish at once.
  const allImages = await Promise.all(dishes.map((dish) =>
    Promise.all((candidates.get(dish.id) ?? []).map((c) => thumbnailData(c.thumbnail)))));
  for (const [dishIndex, dish] of dishes.entries()) {
    const options = candidates.get(dish.id) ?? [];
    const images = allImages[dishIndex];
    const usable = options.filter((_, i) => images[i]);
    if (usable.length === 0) continue;
    parts.push({ text: `Dish ${asked.length}: ${dish.originalName} (${dish.name})` });
    images.filter(Boolean).forEach((image, i) => {
      parts.push({ text: `Photo ${i}:` }, { inlineData: image });
    });
    asked.push({ dish, options: usable });
  }
  const picks = new Map<string, Candidate>();
  if (asked.length === 0) return picks;

  const response = await vertexAI().models.generateContent({
    model: MENU_MODEL,
    contents: [{ role: "user", parts }],
    config: {
      responseMimeType: "application/json",
      responseJsonSchema: {
        type: "object",
        properties: {
          picks: {
            type: "array",
            items: {
              type: "object",
              properties: { dish: { type: "integer" }, photo: { type: "integer" } },
              required: ["dish", "photo"],
            },
          },
        },
        required: ["picks"],
      },
    },
  });
  const raw = JSON.parse(response.text ?? "{}");
  for (const pick of raw.picks ?? []) {
    const entry = asked[pick.dish];
    const choice = entry?.options[pick.photo];
    if (entry && choice) picks.set(entry.dish.id, choice);
  }
  return picks;
}

async function thumbnailData(src: string): Promise<{ data: string; mimeType: string } | null> {
  try {
    const response = await fetch(src, { signal: AbortSignal.timeout(4000) });
    const mimeType = (response.headers.get("content-type") ?? "").split(";")[0];
    if (!response.ok || !mimeType.startsWith("image/")) return null;
    return { data: Buffer.from(await response.arrayBuffer()).toString("base64"), mimeType };
  } catch {
    return null;
  }
}

// The original photo is sharper, but some sites block loading it from elsewhere; then Brave's copy is used.
async function reachable(src: string): Promise<boolean> {
  try {
    const response = await fetch(src, { method: "HEAD", signal: AbortSignal.timeout(2500) });
    return response.ok && (response.headers.get("content-type") ?? "").startsWith("image/");
  } catch {
    return false;
  }
}
