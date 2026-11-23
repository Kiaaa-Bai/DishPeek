// "Can't decide?": plans a whole meal from the scanned menu, so the traveler knows how much to order and
// what goes together (Kia, 2026-11-21: the old version only listed the Peek's Picks again).
//
// One request plans every choice at once: 1 to 6 people times 3 budgets, 18 meals, so switching people or
// budget in the app is instant and costs nothing more (Kia, 2026-11-21). Each dish's reason is written
// once and the meals are lists of ids, which keeps the answer to about 800 tokens: with ~2,000 tokens in,
// about $0.0016 a request, against $0.0007 for one meal at a time; cheaper from the second switch on.

import { vertexAI } from "./vertex";
import { MENU_MODEL } from "./menu";
import * as logger from "firebase-functions/logger";

export type MealDish = {
  id: string;
  name: string; // in the traveler's language
  originalName: string;
  price: number | null;
  contains: string[];
  isCold: boolean;
  isSpicy: boolean;
  isMainDish: boolean;
  peekPick: boolean;
  summary: string;
};

export type Meal = { people: number; tier: number; dishes: string[] };

export type MealRequest = {
  dishes: MealDish[];
  budgets: (number | null)[]; // budget per person for tiers 1, 2, 3, in the menu's currency; null = no limit
  currency: string;
  language: string; // BCP 47, for the reasons
  spice: string | null; // how spicy they like it
  previous: Meal[]; // the last answer, so "Another one" changes the meals
};

export type MealPlans = {
  reasons: { id: string; reason: string }[];
  meals: Meal[];
};

export const PEOPLE = [1, 2, 3, 4, 5, 6];
export const TIERS = [1, 2, 3];

const schema = {
  type: "object",
  properties: {
    reasons: {
      type: "array",
      description: "One entry for every dish used in any meal",
      items: {
        type: "object",
        properties: {
          id: { type: "string", description: "The dish's id, exactly as given" },
          reason: {
            type: "string",
            description: "Why it is a good pick, in the traveler's language, 2 to 6 words, like 'cold starter to share' or 'the house's signature roast'. No dish name, no price.",
          },
        },
        required: ["id", "reason"],
      },
    },
    meals: {
      type: "array",
      description: "One meal for every number of people (1 to 6) and every budget tier (1 to 3): 18 meals",
      items: {
        type: "object",
        properties: {
          people: { type: "integer" },
          tier: { type: "integer" },
          dishes: { type: "array", items: { type: "string" }, description: "Dish ids" },
        },
        required: ["people", "tier", "dishes"],
      },
    },
  },
  required: ["reasons", "meals"],
};

const instructions = `You plan meals at a restaurant for a traveler who can't decide, using only the dishes listed.
Plan one meal for every number of people from 1 to 6 and every budget tier 1, 2 and 3: 18 meals.
Each meal is what people at this kind of restaurant would order together:
- Enough food for the number of people: about one main dish per person, plus a shared starter or side, and a dessert
  or drink when the menu has one and the budget allows. For one person, two or three dishes. For 6, use "6 or more".
- Balance it: mix cold and hot, light and rich, and different meats or fish; don't pick three versions of the same thing.
- Lean on the house's own picks (marked "pick") and well-known local dishes, but not only on them.
- Keep each meal's total within its tier's budget per person times the number of people. Tier 3 has no limit, so it can
  include the house's best and pricier dishes. Dishes without a price can be used when needed.
- Bigger groups build on smaller ones where it makes sense, so the meals feel related.
- Respect how spicy the traveler likes it.
- When previous meals are given, make clearly different meals: change at least half of each meal's dishes.
Then give every dish you used one short reason in the traveler's language. Only use ids from the list.
Write the JSON compactly on one line.`;

export async function planMeals(request: MealRequest): Promise<MealPlans> {
  const menu = request.dishes
    .map((d) => {
      const tags = [
        d.price != null ? `${d.price} ${request.currency}` : "no price",
        d.isMainDish ? "main" : "side",
        d.isCold ? "cold" : "hot",
        d.isSpicy ? "spicy" : "",
        d.peekPick ? "pick" : "",
        d.contains.length ? `has ${d.contains.join("/")}` : "",
      ].filter(Boolean);
      return `${d.id} | ${d.name} (${d.originalName}) | ${tags.join(", ")}${d.summary ? ` | ${d.summary}` : ""}`;
    })
    .join("\n");
  const languageName = new Intl.DisplayNames(["en"], { type: "language" }).of(request.language) ?? request.language;
  const budgets = TIERS.map((tier) => {
    const amount = request.budgets[tier - 1];
    return `tier ${tier}: ${amount != null ? `${Math.round(amount)} ${request.currency} per person` : "no limit"}`;
  });
  const previous = request.previous.map((m) => `${m.people} people, tier ${m.tier}: ${m.dishes.join(", ")}`);
  const text = [
    `Budgets: ${budgets.join("; ")}`,
    `Spice they like: ${request.spice ?? "any"}`,
    `Traveler's language: ${languageName}`,
    previous.length ? `Previous meals, change them:\n${previous.join("\n")}` : "",
    "",
    "Dishes (id | name | facts | what it is):",
    menu,
  ].filter((line) => line !== "").join("\n");

  const response = await vertexAI().models.generateContent({
    model: MENU_MODEL,
    contents: [{ role: "user", parts: [{ text }] }],
    config: {
      systemInstruction: instructions,
      responseMimeType: "application/json",
      responseJsonSchema: schema,
      // Low, so the reasons stay clean words: at 0.6 and 1.0 Flash-Lite wrote garbled Chinese (2026-11-21).
      // "Another one" gets its variety from the previous meals, not from randomness.
      temperature: 0.2,
    },
  });
  logger.info("planMeals usage", { usage: response.usageMetadata });
  const parsed = JSON.parse(response.text ?? "{}") as MealPlans;

  // Only real dishes, each once per meal, and only the 18 meals asked for.
  const known = new Set(request.dishes.map((d) => d.id));
  const meals: Meal[] = [];
  for (const meal of parsed.meals ?? []) {
    if (!PEOPLE.includes(meal.people) || !TIERS.includes(meal.tier)) continue;
    if (meals.some((m) => m.people === meal.people && m.tier === meal.tier)) continue;
    const seen = new Set<string>();
    const dishes = (meal.dishes ?? []).filter((id) => known.has(id) && !seen.has(id) && seen.add(id));
    if (dishes.length) meals.push({ people: meal.people, tier: meal.tier, dishes });
  }
  const used = new Set(meals.flatMap((m) => m.dishes));
  const reasons = (parsed.reasons ?? []).filter((r) => used.has(r.id));
  return { reasons, meals };
}
