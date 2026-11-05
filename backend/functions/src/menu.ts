// Turns the text lines read off a menu photo into a translated menu, with Gemini, in two steps.
// The phone does the reading (Apple Vision, on device, fast). Then:
//   1. readMenu: only what the photo and the list show (names, translations, prices), so the menu
//      is on screen in seconds.
//   2. explainDishes: the rest of each dish (what it is, allergens we can't rule out, how to order),
//      while the user is already looking at the menu.
// Every field in step 1 costs waiting time.
//
// Gemini runs on Vertex AI in this Firebase project, paid from the project's Google Cloud credit.
// The free AI Studio key queued at busy hours: 14–24 s before the first word, even for a three-word
// request (measured 2026-10-26).

import { GoogleGenAI } from "@google/genai";
import * as logger from "firebase-functions/logger";

export const MENU_MODEL = "gemini-3.5-flash-lite";

// One text line read off the photo, with where it is: x, y, width, height from 0 to 1.
export type MenuLine = {
  text: string;
  box: number[];
};

const bilingual = {
  type: "object",
  properties: {
    original: { type: "string" },
    translated: { type: "string" },
  },
  required: ["original", "translated"],
};

// What a dish can contain. The app builds diets (vegetarian, vegan, halal) from these.
const allergen = {
  type: "string",
  enum: [
    "shellfish", "fish", "peanuts", "treeNuts", "dairy", "eggs", "gluten", "soy", "sesame",
    "pork", "beef", "alcohol", "meat", "honey",
  ],
};

// Gemini pretty-prints JSON unless told not to, and the spaces and line breaks were about 40% of
// the tokens it wrote (measured 2026-10-26).
const compact = "Write the JSON compactly on one line, with no spaces or line breaks between its parts.";

const allergenRules = `"meat" means any meat or poultry: add it as well as "pork" or "beef" for those. "alcohol" includes
wine, beer, sake or mirin in the cooking. "fish" includes fish sauce and fish stock; "shellfish" includes
shrimp paste and oyster sauce; "honey" only when honey is used.`;

// The lines as Gemini sees them: number, text, and where the line is.
function lineListing(lines: MenuLine[]): string {
  return lines
    .map((line, index) => `${index}. ${line.text}  [${line.box.map((v) => v.toFixed(3)).join(", ")}]`)
    .join("\n");
}

function projectId(): string {
  return process.env.GCLOUD_PROJECT ?? JSON.parse(process.env.FIREBASE_CONFIG ?? "{}").projectId;
}

// One request to Gemini: instructions, the text, the photo when the app sent one, and the JSON shape
// the answer must have. Returns the parsed answer.
async function ask(label: string, instructions: string, text: string, photo: string | undefined, schema: object) {
  const ai = new GoogleGenAI({ vertexai: true, project: projectId(), location: "global" });
  const parts = photo ? [{ text }, { inlineData: { data: photo, mimeType: "image/jpeg" } }] : [{ text }];
  const response = await ai.models.generateContent({
    model: MENU_MODEL,
    contents: [{ role: "user", parts }],
    config: { systemInstruction: instructions, responseMimeType: "application/json", responseJsonSchema: schema },
  });
  logger.info(`${label} usage`, { usage: response.usageMetadata });
  return JSON.parse(response.text ?? "{}");
}

// MARK: Step 1, read the menu

// What Gemini must send back first. Kept close to the app's ScannedMenu type,
// with only the dish fields the photo and the list rows show.
const menuSchema = {
  type: "object",
  properties: {
    sourceLanguage: { type: "string", description: "BCP 47 code of the menu's language, like ko, ja, zh-Hans, th" },
    currency: { type: "string", description: "ISO 4217 code of the prices, like KRW, JPY, EUR" },
    title: {
      ...bilingual,
      description:
        "The restaurant name as printed on the menu, and in the traveler's language. If no restaurant name is printed, original is an empty string and translated is the word 'Menu' in the traveler's language",
    },
    orderPhrase: { ...bilingual, description: "A polite 'I would like to order' in the menu's language" },
    totalWord: { ...bilingual, description: "The word for 'total' on a bill in the menu's language" },
    defaultQuestion: { ...bilingual, description: "A polite 'What is in it?' in the menu's language" },
    dishes: {
      type: "array",
      items: {
        type: "object",
        properties: {
          lineIndex: {
            type: "integer",
            description:
              "Index of the line that holds this dish's name, never its ingredient or description line. -1 if the OCR missed the name and you only see it in the photo",
          },
          originalName: { type: "string", description: "Just the dish name in the menu's language, OCR mistakes fixed, no size or season notes" },
          priceText: { type: "string", description: "The price exactly as printed, like 11,000" },
          price: { type: "number", description: "The price as a number in major units, or 0 if none" },
          name: { type: "string", description: "The dish's common name for travelers, in the traveler's language" },
          lineTranslation: {
            type: "string",
            description: "A short translation of the printed line, under 30 characters, without the price",
          },
          summary: { type: "string", description: "What kind of dish it is, under 30 characters" },
          isSpicy: { type: "boolean" },
          contains: { type: "array", items: allergen, description: "Allergens it certainly contains" },
          isMainDish: { type: "boolean", description: "False for sides, extras, rice and drinks" },
        },
        required: [
          "lineIndex", "originalName", "priceText", "price", "name", "lineTranslation", "summary",
          "isSpicy", "contains", "isMainDish",
        ],
      },
    },
  },
  required: ["sourceLanguage", "currency", "title", "orderPhrase", "totalWord", "defaultQuestion", "dishes"],
};

const readInstructions = `You help travelers read restaurant menus in a language they do not know.
You get the text lines read off a menu photo by on-device OCR, top to bottom, each with its position
(x, y, width, height from 0 to 1), and the traveler's language. Usually you also get the photo itself:
use it to fix OCR mistakes and to find dish names the OCR missed (short ones are often missed).
Match every dish to the OCR line that holds its name, even when the OCR misspelled it; use -1 only
when no line is close.

Group the lines into dishes. A dish name and its price are often on one line, or side by side.
On set and tasting menus a dish often takes two lines: its name, then a smaller line just below
listing its ingredients. That is one dish, and lineIndex is the name line.
Every dish name on the menu becomes a dish, with or without a price.
A section heading (like Starters or Dessert) is not a dish, but the items under it are.
Skip lines that are not dishes, except the restaurant name (title).
Fix obvious OCR mistakes. Write every translated field in the traveler's language.
Put an allergen in "contains" only when it is listed or certain.
${allergenRules}
Keep translations short and plain, the way a friend who lives there would explain it.
${compact}`;

export type ScannedMenu = {
  sourceLanguage: string;
  targetLanguage: string;
  currency: string;
  title: { original: string; translated: string };
  orderPhrase: { original: string; translated: string };
  totalWord: { original: string; translated: string };
  defaultQuestion: { original: string; translated: string };
  dishes: Array<Record<string, unknown>>;
};

// A stable id for a dish across scans and users: its name with spaces and punctuation removed.
export function dishId(originalName: string): string {
  return originalName.normalize("NFKC").toLowerCase().replace(/[^\p{L}\p{N}]/gu, "") || "dish";
}

// photo: the menu photo as base64 JPEG, when the app sends it.
// One request for the whole menu: split into parts, prices that sit on their own lines got paired
// with the wrong dish, and it was slower (tested 2026-10-26).
export async function readMenu(
  lines: MenuLine[],
  targetLanguage: string,
  photo?: string,
): Promise<ScannedMenu> {
  const text = `Traveler's language: ${targetLanguage}\n\nMenu lines:\n${lineListing(lines)}`;
  const raw = await ask("readMenu", readInstructions, text, photo, menuSchema);
  const usedIds = new Set<string>();

  const dishes = (raw.dishes ?? []).map((dish: Record<string, any>) => {
    // Two dishes can share a name on one menu (sizes, sections); keep ids unique.
    let id = dishId(String(dish.originalName ?? ""));
    while (usedIds.has(id)) id += "-2";
    usedIds.add(id);

    // A dish Gemini only saw in the photo has no line, so no box on the photo.
    const line = dish.lineIndex >= 0 ? lines[dish.lineIndex] : undefined;
    return {
      id,
      printed: dish.originalName,
      originalName: dish.originalName,
      priceText: dish.priceText,
      price: dish.price > 0 ? dish.price : undefined,
      box: line?.box,
      lineText: line?.text,
      name: dish.name,
      lineTranslation: dish.lineTranslation,
      summary: dish.summary,
      isSpicy: Boolean(dish.isSpicy),
      contains: dish.contains ?? [],
      isMainDish: dish.isMainDish !== false,
      // Step 2 fills these in. Until then: empty, and "×1" to order one.
      whatItIs: "",
      details: "",
      isCold: false,
      unsure: [],
      amount: { original: "×1", translated: "×1" },
      photos: [],
      knownFor: false,
      dishPeekOrders: 0,
      houseSpecial: false,
      localClassic: false,
    };
  });

  return {
    sourceLanguage: raw.sourceLanguage,
    targetLanguage,
    currency: raw.currency,
    title: raw.title,
    orderPhrase: raw.orderPhrase,
    totalWord: raw.totalWord,
    defaultQuestion: raw.defaultQuestion,
    dishes,
  };
}

// MARK: Step 2, explain each dish

// What Gemini must send back for each dish found in step 1, by the dish's number.
const detailsSchema = {
  type: "object",
  properties: {
    footer: { ...bilingual, description: "A general note printed on the menu, if any, else empty strings" },
    dishes: {
      type: "array",
      items: {
        type: "object",
        properties: {
          dish: { type: "integer", description: "The dish's number in the list of dishes" },
          pronunciation: { type: "string", description: "Romanized pronunciation if the menu's script is not Latin, else empty" },
          whatItIs: { type: "string", description: "Main ingredients, under 45 characters" },
          details: { type: "string", description: "One or two plain sentences: what it is and how it tastes" },
          spiceTip: { type: "string", description: "For spicy dishes, a short tip about the heat, else empty" },
          isCold: { type: "boolean", description: "Served cold" },
          unsure: {
            type: "array",
            items: {
              type: "object",
              properties: {
                allergen,
                why: { type: "string", description: "Short reason we cannot rule it out, in the traveler's language" },
              },
              required: ["allergen", "why"],
            },
          },
          amount: { ...bilingual, description: "How to order one, with the right counter word, like 1개 / ×1" },
          question: { ...bilingual, description: "The most useful question to ask staff about this dish, or empty strings" },
          houseSpecial: {
            type: "boolean",
            description:
              "True only if the menu singles this dish out from the others: circled, starred, boxed, highlighted, or labelled as a house special, signature, chef's recommendation or best seller. A bullet or symbol that starts every line is not a mark",
          },
          localClassic: {
            type: "boolean",
            description:
              "True if this is a well-known signature dish of this cuisine or region that a visitor should try. At most 3 dishes per menu",
          },
          wikiTitle: {
            type: "string",
            description:
              "Exact title of the English Wikipedia article about this dish, like Kalguksu or Khao soi. Empty if you are not sure one exists",
          },
        },
        required: [
          "dish", "pronunciation", "whatItIs", "details", "spiceTip", "isCold", "unsure", "amount",
          "question", "houseSpecial", "localClassic", "wikiTitle",
        ],
      },
    },
  },
  required: ["footer", "dishes"],
};

const explainInstructions = `You help travelers understand the dishes on a restaurant menu in a language they do not know.
You get the text lines read off the menu photo by on-device OCR, top to bottom, each with its position
(x, y, width, height from 0 to 1), usually the photo itself, the traveler's language, and the list of
dishes already found on the menu. Explain every dish in the list, by its number.
On set and tasting menus a smaller line just below a dish name lists its ingredients: use it for
whatItIs and details. Write every translated field in the traveler's language.
Never say a dish is safe for an allergy. Put an allergen in "unsure" when common versions of the dish
have it and it is not already in the dish's "contains", with a short reason.
${allergenRules}
Keep it short and plain, the way a friend who lives there would explain it.
${compact}`;

// A dish from step 1, as the app sends it back.
export type DishToExplain = {
  id: string;
  originalName: string;
  name: string;
  box?: number[];
  contains: string[];
};

export type DishDetails = {
  pronunciation?: string;
  whatItIs: string;
  details: string;
  spiceTip?: string;
  isCold: boolean;
  unsure: Array<{ allergen: string; why: string }>;
  amount: { original: string; translated: string };
  question?: { original: string; translated: string };
  houseSpecial: boolean;
  localClassic: boolean;
  wikiTitle?: string;
};

export type Explained = {
  footer?: { original: string; translated: string };
  dishes: Record<string, DishDetails>;
};

export async function explainDishes(
  lines: MenuLine[],
  targetLanguage: string,
  dishes: DishToExplain[],
  photo?: string,
): Promise<Explained> {
  // Each dish with the line its name is on, found by its box, so Gemini can read the line below it.
  const listing = dishes
    .map((dish, index) => {
      const line = dish.box ? lines.findIndex((l) => l.box.every((v, i) => v === dish.box?.[i])) : -1;
      const where = line >= 0 ? `, on line ${line}` : "";
      const contains = dish.contains.length > 0 ? `, contains ${dish.contains.join(", ")}` : "";
      return `${index}. ${dish.originalName} (${dish.name})${where}${contains}`;
    })
    .join("\n");
  const text = `Traveler's language: ${targetLanguage}\n\nMenu lines:\n${lineListing(lines)}\n\nDishes:\n${listing}`;

  const raw = await ask("explainDishes", explainInstructions, text, photo, detailsSchema);
  const items: Array<Record<string, any>> = raw.dishes ?? [];
  // A mark on most of the dishes is decoration (bullets), not a pick.
  const marked = items.filter((item) => item.houseSpecial).length;
  const marksMeanNothing = marked > dishes.length / 2;

  const details: Record<string, DishDetails> = {};
  for (const item of items) {
    const dish = dishes[item.dish];
    if (!dish) continue;
    details[dish.id] = {
      pronunciation: item.pronunciation || undefined,
      whatItIs: item.whatItIs ?? "",
      details: item.details ?? "",
      spiceTip: item.spiceTip || undefined,
      isCold: Boolean(item.isCold),
      unsure: item.unsure ?? [],
      amount: item.amount?.original ? item.amount : { original: "×1", translated: "×1" },
      question: item.question?.original ? item.question : undefined,
      houseSpecial: Boolean(item.houseSpecial) && !marksMeanNothing,
      localClassic: Boolean(item.localClassic),
      wikiTitle: item.wikiTitle || undefined,
    };
  }

  return {
    footer: raw.footer?.original ? raw.footer : undefined,
    dishes: details,
  };
}
