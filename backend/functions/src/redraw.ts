// Redraws the whole menu photo with its text in the traveler's language, using a Gemini image model,
// so the menu reads as if it had been printed in that language.
// It gets the dish lines scanMenu already translated, so the picture says the same as the list,
// and the app can find each dish on the new picture by reading it again.
// Runs on Vertex AI in this Firebase project (billed to the project, no API key).
//
// Tested 2026-10-26 on 10 menus: Pro kept all 92 readable prices, about 31 s and $0.14 an image;
// Nano Banana was slower and changed prices on a dense menu.

import { vertexAI } from "./vertex";

export const REDRAW_MODEL = "gemini-3-pro-image";

// The shapes the image model can draw. The app sends the one closest to its photo.
export const ASPECT_RATIOS = ["1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9"];

// A line as printed, and what to write in its place.
export type Translation = { original: string; translated: string };

const prompt = (language: string, translations: Translation[]) => `This is a photo of a restaurant menu. Translate the menu's text into ${language}
and give back the same photo with the translation printed in place of the original words.

Rules:
- Copy every number exactly as printed: prices, decimals, separators, currency signs and item numbers.
  Never change, add or remove a digit.
- Keep every line where it is, in the same order. Do not add dishes and do not leave any out.
- Match the original lettering: handwriting stays handwriting, chalk stays chalk, and keep the size,
  colour, weight and slant of each line.
- Change nothing that is not text: the paper or board, frame, food photos, lighting, angle and crop.
- Keep the restaurant's name as printed.
- If a line cannot be read, leave it as it is.

Write these lines exactly as given here (printed line → what to write instead):
${translations.map((t) => `"${t.original}" → "${t.translated}"`).join("\n")}
Translate every other line yourself.`;

export type Redrawn = {
  image: string; // base64
  mimeType: string;
};

// photo: base64 JPEG. language: BCP 47 code. aspectRatio: one of ASPECT_RATIOS.
export async function redrawMenu(photo: string, language: string, aspectRatio: string, translations: Translation[]): Promise<Redrawn> {
  const languageName = new Intl.DisplayNames(["en"], { type: "language" }).of(language) ?? language;
  const response = await vertexAI().models.generateContent({
    model: REDRAW_MODEL,
    contents: [
      {
        role: "user",
        parts: [{ text: prompt(languageName, translations) }, { inlineData: { data: photo, mimeType: "image/jpeg" } }],
      },
    ],
    config: { responseModalities: ["IMAGE"], imageConfig: { aspectRatio, imageSize: "2K" } },
  });
  const part = response.candidates?.[0]?.content?.parts?.find((p) => p.inlineData?.data);
  if (!part?.inlineData?.data) {
    throw new Error(`no image in the reply: ${JSON.stringify(response.candidates?.[0]?.finishReason ?? response.promptFeedback)}`);
  }
  return { image: part.inlineData.data, mimeType: part.inlineData.mimeType ?? "image/png" };
}
