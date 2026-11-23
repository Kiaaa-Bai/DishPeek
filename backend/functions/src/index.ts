// DishPeek backend. The app calls these with the Firebase SDK; API keys never leave the server.
//
//   scanMenu        menu text lines in, translated menu out (Gemini), only what the screens show first
//   explainDishes   the rest of each dish, asked for once the menu is on screen
//   redrawMenu      the whole menu photo redrawn in the traveler's language (image model)
//   nearbyPlace     location in, the restaurant and its Google rating out (Places API)
//   placePopularity what the place is known for (Gemini + Google Maps) and DishPeek order counts
//   recordOrder     counts the dishes in an order, for "#1 on DishPeek"
//   dishPhotos      a typical photo of each dish (Wikipedia, then a web image search picked by Gemini)
//   planMeal        "Can't decide?": a whole meal from the menu for some people and a budget (Gemini)

import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";

import { readMenu, explainDishes as explain, type MenuLine, type DishToExplain } from "./menu";
import { findPlace } from "./places";
import { knownFor, type DishRef } from "./popular";
import { findPhotos, wikipedia, type DishQuery } from "./photos";
import { webPhotos } from "./webphotos";
import { redrawMenu as redraw, ASPECT_RATIOS, type Translation } from "./redraw";
import { planMeals, type MealDish, type Meal } from "./meal";

initializeApp();
const db = getFirestore();

// A cap on how many copies run at once, so a bug or abuse can't run up the bill.
setGlobalOptions({ region: "us-central1", maxInstances: 10 });

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const PLACES_API_KEY = defineSecret("PLACES_API_KEY");
// Brave Search API, for dish photos Wikipedia doesn't have. Kia sets it himself.
const BRAVE_API_KEY = defineSecret("BRAVE_API_KEY");

function requireNumber(value: unknown, name: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new HttpsError("invalid-argument", `${name} must be a number`);
  }
  return value;
}

function requireLanguage(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$/.test(value)) {
    throw new HttpsError("invalid-argument", "language must be a BCP 47 code");
  }
  return value;
}

// The menu's text lines and photo, as the app sends them to scanMenu and explainDishes.
function scanInput(data: any): { lines: MenuLine[]; photo?: string } {
  const { lines, photo } = data ?? {};
  if (!Array.isArray(lines) || lines.length === 0 || lines.length > 300) {
    throw new HttpsError("invalid-argument", "lines must be a list of 1 to 300 text lines");
  }
  return {
    lines: lines.map((line: any) => ({
      text: String(line?.text ?? "").slice(0, 200),
      box: Array.isArray(line?.box) ? line.box.slice(0, 4).map(Number) : [0, 0, 0, 0],
    })),
    // The menu photo, as base64 JPEG. Optional: the text alone still works.
    photo: typeof photo === "string" && photo.length > 0 && photo.length < 4_000_000 ? photo : undefined,
  };
}

// A function that has not run for a while takes a few seconds to start ("cold start").
// The app sends { warmup: true } to the scan functions when the camera opens, so they are already
// running when the photo comes. Answers at once, does no work, costs next to nothing.
function isWarmUp(data: any): boolean {
  return data?.warmup === true;
}

// Both menu functions use Gemini on Vertex AI (no key; billed to this project), see menu.ts.
export const scanMenu = onCall(
  { timeoutSeconds: 60, memory: "512MiB" },
  async (request) => {
    if (isWarmUp(request.data)) return { warm: true };
    const { lines, photo } = scanInput(request.data);
    const language = requireLanguage(request.data?.targetLanguage);
    const started = Date.now();
    try {
      const menu = await readMenu(lines, language, photo);
      logger.info("scanMenu", { lines: lines.length, dishes: menu.dishes.length, photo: !!photo, ms: Date.now() - started });
      return menu;
    } catch (error) {
      logger.error("scanMenu failed", error);
      throw new HttpsError("internal", "Could not read this menu");
    }
  },
);

// The app calls this right after scanMenu, with the dishes it found, while the menu is already on screen.
export const explainDishes = onCall(
  { timeoutSeconds: 120, memory: "512MiB" },
  async (request) => {
    if (isWarmUp(request.data)) return { warm: true };
    const { lines, photo } = scanInput(request.data);
    const language = requireLanguage(request.data?.targetLanguage);
    const { dishes } = request.data ?? {};
    if (!Array.isArray(dishes) || dishes.length === 0 || dishes.length > 150) {
      throw new HttpsError("invalid-argument", "dishes must be a list of 1 to 150 dishes");
    }
    const list: DishToExplain[] = dishes.map((d: any) => ({
      id: String(d?.id ?? ""),
      originalName: String(d?.originalName ?? "").slice(0, 100),
      name: String(d?.name ?? "").slice(0, 100),
      box: Array.isArray(d?.box) ? d.box.slice(0, 4).map(Number) : undefined,
      contains: Array.isArray(d?.contains) ? d.contains.slice(0, 20).map(String) : [],
    }));
    const started = Date.now();
    try {
      const explained = await explain(lines, language, list, photo);
      logger.info("explainDishes", { dishes: list.length, explained: Object.keys(explained.dishes).length, ms: Date.now() - started });
      return explained;
    } catch (error) {
      logger.error("explainDishes failed", error);
      throw new HttpsError("internal", "Could not explain these dishes");
    }
  },
);

// "Can't decide?": every meal at once, for 1 to 6 people and three budgets, from the dishes the app sends
// (already without the ones this person avoids), so switching in the app is instant.
export const planMeal = onCall({ timeoutSeconds: 60, memory: "256MiB" }, async (request) => {
  if (isWarmUp(request.data)) return { warm: true };
  const data = request.data ?? {};
  const language = requireLanguage(data.targetLanguage);
  if (!Array.isArray(data.dishes) || data.dishes.length === 0 || data.dishes.length > 150) {
    throw new HttpsError("invalid-argument", "dishes must be a list of 1 to 150 dishes");
  }
  const dishes: MealDish[] = data.dishes.map((d: any) => ({
    id: String(d?.id ?? "").slice(0, 60),
    name: String(d?.name ?? "").slice(0, 100),
    originalName: String(d?.originalName ?? "").slice(0, 100),
    price: typeof d?.price === "number" && Number.isFinite(d.price) ? d.price : null,
    contains: Array.isArray(d?.contains) ? d.contains.slice(0, 20).map(String) : [],
    isCold: Boolean(d?.isCold),
    isSpicy: Boolean(d?.isSpicy),
    isMainDish: d?.isMainDish !== false,
    peekPick: Boolean(d?.peekPick),
    summary: String(d?.summary ?? "").slice(0, 160),
  }));
  const budgets = [0, 1, 2].map((i) => {
    const value = Array.isArray(data.budgets) ? data.budgets[i] : null;
    return typeof value === "number" && value > 0 ? value : null;
  });
  const previous: Meal[] = Array.isArray(data.previous)
    ? data.previous.slice(0, 18).map((m: any) => ({
        people: Number(m?.people) || 0,
        tier: Number(m?.tier) || 0,
        dishes: Array.isArray(m?.dishes) ? m.dishes.slice(0, 12).map(String) : [],
      }))
    : [];
  const started = Date.now();
  try {
    const plans = await planMeals({
      dishes,
      budgets,
      currency: String(data.currency ?? "").slice(0, 3),
      language,
      spice: typeof data.spice === "string" ? data.spice.slice(0, 20) : null,
      previous,
    });
    logger.info("planMeal", { dishes: dishes.length, meals: plans.meals.length, ms: Date.now() - started });
    return plans;
  } catch (error) {
    logger.error("planMeal failed", error);
    throw new HttpsError("internal", "Could not plan a meal");
  }
});

// The app calls this after scanMenu with its translations, so the picture says the same as the list.
export const redrawMenu = onCall({ timeoutSeconds: 120, memory: "1GiB" }, async (request) => {
  if (isWarmUp(request.data)) return { warm: true };
  const { photo, aspectRatio, translations } = request.data ?? {};
  if (typeof photo !== "string" || photo.length === 0 || photo.length > 8_000_000) {
    throw new HttpsError("invalid-argument", "photo must be a base64 JPEG under 6 MB");
  }
  const language = requireLanguage(request.data?.targetLanguage);
  const ratio = ASPECT_RATIOS.includes(aspectRatio) ? aspectRatio : "3:4";
  // One instruction per printed line: when the OCR reads two lines as the same text, two different
  // translations for it made the model shift names against prices (German menu, 2026-11-19).
  const seen = new Set<string>();
  const list: Translation[] = (Array.isArray(translations) ? translations : []).slice(0, 300).map((t: any) => ({
    original: String(t?.original ?? "").slice(0, 200),
    translated: String(t?.translated ?? "").slice(0, 200),
  })).filter((t: Translation) => t.original && t.translated && !seen.has(t.original) && seen.add(t.original));
  const started = Date.now();
  try {
    const { model, tries, ...picture } = await redraw(photo, language, ratio, list);
    logger.info("redrawMenu", { lines: list.length, ratio, model, tries, kb: Math.round(picture.image.length / 1024), ms: Date.now() - started });
    return picture;
  } catch (error) {
    logger.error("redrawMenu failed", error);
    throw new HttpsError("internal", "Could not redraw this menu");
  }
});

export const nearbyPlace = onCall({ secrets: [PLACES_API_KEY] }, async (request) => {
  const { latitude, longitude, languageCode, nameHint } = request.data ?? {};
  try {
    const place = await findPlace(
      PLACES_API_KEY.value(),
      requireNumber(latitude, "latitude"),
      requireNumber(longitude, "longitude"),
      requireLanguage(languageCode),
      typeof nameHint === "string" ? nameHint.slice(0, 100) : undefined,
    );
    return { place };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    logger.error("nearbyPlace failed", error);
    throw new HttpsError("internal", "Could not find the restaurant");
  }
});

export const placePopularity = onCall(
  { secrets: [GEMINI_API_KEY], timeoutSeconds: 60 },
  async (request) => {
    const { placeId, placeName, latitude, longitude, dishes } = request.data ?? {};
    if (typeof placeId !== "string" || !placeId || placeId.includes("/")) {
      throw new HttpsError("invalid-argument", "placeId is required");
    }
    const refs: DishRef[] = (Array.isArray(dishes) ? dishes : []).slice(0, 60).map((d: any) => ({
      id: String(d?.id ?? ""),
      originalName: String(d?.originalName ?? ""),
      name: String(d?.name ?? ""),
    })).filter((d: DishRef) => d.id && !d.id.includes("/"));

    // DishPeek order counts for these dishes at this place.
    const counts: Record<string, number> = {};
    if (refs.length > 0) {
      const docs = await db.getAll(...refs.map((d) => db.doc(`places/${placeId}/dishes/${d.id}`)));
      for (const doc of docs) {
        counts[doc.id] = doc.exists ? Number(doc.get("orders") ?? 0) : 0;
      }
    }

    let known = { ids: [] as string[], sources: [] as Array<{ title: string; url: string }> };
    try {
      known = await knownFor(
        GEMINI_API_KEY.value(),
        String(placeName ?? ""),
        requireNumber(latitude, "latitude"),
        requireNumber(longitude, "longitude"),
        refs,
      );
    } catch (error) {
      // Popularity is a nice-to-have: the menu still works without it.
      logger.warn("knownFor failed", error);
    }

    return { knownFor: known.ids, sources: known.sources, orders: counts };
  },
);

// The app asks for these after the menu is on screen, so pictures never slow down reading it.
// Wikipedia first (free); for the rest, the shared cache, then Brave image search with a Gemini pick.
export const dishPhotos = onCall({ timeoutSeconds: 60, memory: "512MiB", secrets: [BRAVE_API_KEY] }, async (request) => {
  if (isWarmUp(request.data)) return { warm: true };
  const { dishes } = request.data ?? {};
  const queries: DishQuery[] = (Array.isArray(dishes) ? dishes : []).slice(0, 60).map((d: any) => ({
    id: String(d?.id ?? ""),
    originalName: String(d?.originalName ?? "").slice(0, 100),
    name: String(d?.name ?? "").slice(0, 100),
    wikiTitle: typeof d?.wikiTitle === "string" ? d.wikiTitle.slice(0, 100) : undefined,
  })).filter((d: DishQuery) => d.id && !d.id.includes("/"));

  // The app asks twice: "quick" (Wikipedia and the cache, a second or two), then the rest with the search,
  // so the photos that are ready show up without waiting for the search.
  const quick = request.data?.quick === true;
  const photos = await findPhotos(queries, [wikipedia, webPhotos(db, BRAVE_API_KEY.value(), !quick)]);
  logger.info("dishPhotos", { asked: queries.length, found: Object.keys(photos).length, quick });
  return { photos };
});

export const recordOrder = onCall(async (request) => {
  const { placeId, dishIds } = request.data ?? {};
  if (typeof placeId !== "string" || !placeId || placeId.includes("/")) {
    throw new HttpsError("invalid-argument", "placeId is required");
  }
  if (!Array.isArray(dishIds) || dishIds.length === 0 || dishIds.length > 20) {
    throw new HttpsError("invalid-argument", "dishIds must be a list of 1 to 20 ids");
  }
  const batch = db.batch();
  for (const id of new Set(dishIds.map(String))) {
    if (!id || id.includes("/") || id.length > 100) continue;
    batch.set(
      db.doc(`places/${placeId}/dishes/${id}`),
      { orders: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  }
  await batch.commit();
  return { ok: true };
});

