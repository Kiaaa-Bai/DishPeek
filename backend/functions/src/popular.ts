// Which dishes a restaurant is known for, from Gemini grounded in Google Maps.
// Google requires the Maps sources to be shown right under this answer, so they are returned with it.

import { GoogleGenAI } from "@google/genai";

export const MAPS_MODEL = "gemini-3.5-flash-lite";

export type DishRef = {
  id: string;
  originalName: string;
  name: string;
};

export type KnownFor = {
  ids: string[];
  sources: Array<{ title: string; url: string }>;
};

export async function knownFor(
  apiKey: string,
  placeName: string,
  latitude: number,
  longitude: number,
  dishes: DishRef[],
): Promise<KnownFor> {
  if (dishes.length === 0) return { ids: [], sources: [] };

  const ai = new GoogleGenAI({ apiKey });
  // Maps grounding only takes English prompts.
  const list = dishes.map((d) => `- ${d.id}: ${d.originalName} (${d.name})`).join("\n");
  const prompt = `The restaurant "${placeName}" is at the user's location.
According to Google Maps, which of these dishes is this restaurant known for?

${list}

Reply with only the ids of the dishes it is known for, best first, separated by commas.
Reply NONE if Google Maps does not show it being known for any of them.`;

  const interaction = await ai.interactions.create({
    model: MAPS_MODEL,
    input: prompt,
    tools: [{ type: "google_maps", latitude, longitude }],
  });

  const valid = new Set(dishes.map((d) => d.id));
  const ids = (interaction.output_text ?? "")
    .split(/[\s,]+/)
    .map((token) => token.trim())
    .filter((token) => valid.has(token));

  // Every Google Maps place cited for the answer, without repeats.
  const sources = new Map<string, string>();
  for (const step of (interaction as any).steps ?? []) {
    if (step.type !== "model_output") continue;
    for (const block of step.content ?? []) {
      for (const note of block.annotations ?? []) {
        if (note.type === "place_citation" && note.url) {
          sources.set(note.url, note.name ?? "Google Maps");
        }
      }
    }
  }

  return {
    ids: [...new Set(ids)].slice(0, 3),
    sources: [...sources].map(([url, title]) => ({ title, url })),
  };
}
