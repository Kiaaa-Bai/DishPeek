// Finds a picture of each dish, to show what it usually looks like.
// Finders are tried in order, and each one only looks for the dishes still without a picture.
// Today: Wikipedia (free, and its photos may be reused with credit).
// Next: a web image search, such as Brave, for the dishes Wikipedia does not have.
//
// These are typical photos, not this restaurant's. The restaurant's own Google photos
// may not be matched to dishes by an AI: Google Maps terms forbid creating content from them.

import * as logger from "firebase-functions/logger";

export type DishQuery = {
  id: string;
  originalName: string;
  name: string;
  wikiTitle?: string;
};

export type DishPicture = {
  url: string;
  credit: string; // who took it and under what license, shown under the photo
  link: string; // where the photo and its license live
  source: "wikipedia" | "web";
};

export type PhotoFinder = {
  name: string;
  find(dishes: DishQuery[]): Promise<Record<string, DishPicture>>;
};

export async function findPhotos(dishes: DishQuery[], finders: PhotoFinder[]): Promise<Record<string, DishPicture>> {
  const found: Record<string, DishPicture> = {};
  for (const finder of finders) {
    const missing = dishes.filter((dish) => !found[dish.id]);
    if (missing.length === 0) break;
    try {
      Object.assign(found, await finder.find(missing));
    } catch (error) {
      // One finder failing should not cost the pictures another can still find.
      logger.warn(`${finder.name} photo finder failed`, error);
    }
  }
  return found;
}

// MARK: Wikipedia

// Wikimedia asks every app to say who it is, with a way to reach the developer.
const USER_AGENT = "DishPeek/0.1 (https://github.com/Kiaaa-Bai/molab-2026-itp-kia; class project)";

async function askWikipedia(params: Record<string, string>): Promise<any> {
  const url = new URL("https://en.wikipedia.org/w/api.php");
  url.search = new URLSearchParams({ action: "query", format: "json", formatversion: "2", ...params }).toString();
  const response = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
  if (!response.ok) {
    throw new Error(`Wikipedia ${response.status}`);
  }
  return response.json();
}

// HTML in Commons credits, like <a href="...">Name</a>, down to plain text.
function plainText(html: string): string {
  return html.replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim();
}

export const wikipedia: PhotoFinder = {
  name: "wikipedia",

  async find(dishes) {
    const titles = [...new Set(dishes.map((dish) => dish.wikiTitle?.trim()).filter((t): t is string => !!t))].slice(0, 50);
    if (titles.length === 0) return {};

    // 1. Each article's lead image.
    const pages = await askWikipedia({
      titles: titles.join("|"),
      redirects: "1",
      prop: "pageimages",
      piprop: "thumbnail|name",
      pithumbsize: "960",
    });

    // The title we asked for can come back spelled differently, or redirected to another article.
    const renamed = new Map<string, string>();
    for (const step of [...(pages.query?.normalized ?? []), ...(pages.query?.redirects ?? [])]) {
      renamed.set(step.from, step.to);
    }
    const finalTitle = (title: string) => {
      let current = title;
      for (let i = 0; i < 3 && renamed.has(current); i++) current = renamed.get(current)!;
      return current;
    };

    const imageOf = new Map<string, { url: string; file: string }>();
    for (const page of pages.query?.pages ?? []) {
      if (page.thumbnail?.source && page.pageimage) {
        imageOf.set(page.title, { url: page.thumbnail.source, file: page.pageimage });
      }
    }
    if (imageOf.size === 0) return {};

    // 2. Who took each photo, and its license. Only freely licensed photos may be shown.
    const files = [...new Set([...imageOf.values()].map((image) => `File:${image.file}`))];
    const info = await askWikipedia({
      titles: files.join("|"),
      prop: "imageinfo",
      iiprop: "extmetadata",
      iiextmetadatafilter: "Artist|LicenseShortName",
    });
    const creditOf = new Map<string, string>();
    for (const page of info.query?.pages ?? []) {
      const meta = page.imageinfo?.[0]?.extmetadata;
      const license = plainText(meta?.LicenseShortName?.value ?? "");
      if (!/^(CC|Public domain|PD)/i.test(license)) continue;
      const artist = plainText(meta?.Artist?.value ?? "").slice(0, 60) || "Unknown";
      creditOf.set(String(page.title).replace(/^File:/, "").replace(/ /g, "_"), `${artist} · ${license} · Wikimedia Commons`);
    }

    const found: Record<string, DishPicture> = {};
    for (const dish of dishes) {
      if (!dish.wikiTitle) continue;
      const image = imageOf.get(finalTitle(dish.wikiTitle.trim()));
      const credit = image && creditOf.get(image.file.replace(/ /g, "_"));
      if (!image || !credit) continue;
      found[dish.id] = {
        url: image.url,
        credit,
        link: `https://commons.wikimedia.org/wiki/File:${encodeURIComponent(image.file)}`,
        source: "wikipedia",
      };
    }
    return found;
  },
};
