// Redraws the whole menu photo with its text in the traveler's language, using a Gemini image model,
// so the menu reads as if it had been printed in that language.
// It gets the dish lines scanMenu already translated, so the picture says the same as the list,
// and the app can find each dish on the new picture by reading it again.
// Runs on Vertex AI in this Firebase project (billed to the project, no API key).
//
// Tested 2026-10-26 on 10 menus: Pro kept all 92 readable prices, about 31 s and $0.14 an image;
// Nano Banana was slower and changed prices on a dense menu.
// Tested 2026-11-19 with scanMenu's translations: Flash-Lite took 3–9 s and kept every price on the
// German, French and Korean menus, against 25–46 s for Pro. Speed matters more than perfect lettering,
// so Flash-Lite goes first. It can only draw 1K.
// The prompt says outright to replace the words, not add to them: on handwritten menus Flash-Lite kept
// the original next to the translation (Kia, 2026-11-19), helped by the old "leave unreadable lines" rule.
//
// Flash-Lite often answers 429 (busy): Google shares its capacity among all customers, so this is
// not our quota. Wait a moment and ask again; if it is still busy, Pro draws the menu instead.
// If Pro fails too, the error goes back to the app, which writes the translation over each line.

import { vertexAI } from "./vertex";

export const REDRAW_MODEL = "gemini-3.1-flash-lite-image";
export const FALLBACK_MODEL = "gemini-3-pro-image";

// How long to wait before asking Flash-Lite again after a 429: two more tries in all.
const RETRY_WAITS_MS = [1000, 2000];

// The shapes the image model can draw. The app sends the one closest to its photo.
export const ASPECT_RATIOS = ["1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9"];

// A line as printed, and what to write in its place.
export type Translation = { original: string; translated: string };

const prompt = (language: string, translations: Translation[]) => `This is a photo of a restaurant menu. Translate the menu's text into ${language}
and give back the same photo with the translation printed in place of the original words.

Rules:
- Replace the words, don't add to them: erase each original line and write only its ${language} translation
  in its place. The finished menu shows ${language} only, never the original words next to the translation.
  The only things kept as printed are the restaurant's name, numbers and currency signs.
- Copy every number exactly as printed: prices, decimals, separators, currency signs and item numbers.
  Never change, add or remove a digit.
- Keep every line where it is, in the same order. Do not add dishes and do not leave any out.
- Match the original lettering: handwriting stays handwriting, chalk stays chalk, and keep the size,
  colour, weight and slant of each line.
- Change nothing that is not text: the paper or board, frame, food photos, lighting, angle and crop.
- Hard-to-read handwriting still gets translated, from the list below or your best reading of it.
  Leave a line untouched only if you cannot make out any of it.

The list below says what to write in place of each line. Its printed lines were read by OCR and may be
misspelled: match each one to the line on the photo it most likely is.
${translations.map((t) => `"${t.original}" → "${t.translated}"`).join("\n")}
Translate every other line yourself.`;

export type Redrawn = {
  image: string; // base64
  mimeType: string;
  model: string; // which model drew it, for the logs
  tries: number; // how many times Flash-Lite was asked
};

// photo: base64 JPEG. language: BCP 47 code. aspectRatio: one of ASPECT_RATIOS.
export async function redrawMenu(photo: string, language: string, aspectRatio: string, translations: Translation[]): Promise<Redrawn> {
  const languageName = new Intl.DisplayNames(["en"], { type: "language" }).of(language) ?? language;
  const text = prompt(languageName, translations);

  let tries = 0;
  while (true) {
    tries += 1;
    try {
      const picture = await draw(REDRAW_MODEL, "1K", text, photo, aspectRatio);
      return { ...picture, model: REDRAW_MODEL, tries };
    } catch (error) {
      const wait = RETRY_WAITS_MS[tries - 1];
      // Only "busy" is worth asking again; anything else, or busy too long, goes to Pro.
      if (!isBusy(error) || wait === undefined) break;
      await new Promise((resolve) => setTimeout(resolve, wait));
    }
  }
  const picture = await draw(FALLBACK_MODEL, "2K", text, photo, aspectRatio);
  return { ...picture, model: FALLBACK_MODEL, tries };
}

// One request to an image model: the instructions and the photo in, one picture out.
async function draw(model: string, imageSize: string, text: string, photo: string, aspectRatio: string) {
  const response = await vertexAI().models.generateContent({
    model,
    contents: [{ role: "user", parts: [{ text }, { inlineData: { data: photo, mimeType: "image/jpeg" } }] }],
    config: { responseModalities: ["IMAGE"], imageConfig: { aspectRatio, imageSize } },
  });
  const part = response.candidates?.[0]?.content?.parts?.find((p) => p.inlineData?.data);
  if (!part?.inlineData?.data) {
    throw new Error(`no image in the reply: ${JSON.stringify(response.candidates?.[0]?.finishReason ?? response.promptFeedback)}`);
  }
  return { image: part.inlineData.data, mimeType: part.inlineData.mimeType ?? "image/png" };
}

// True when Vertex said it is too busy right now (HTTP 429, RESOURCE_EXHAUSTED).
function isBusy(error: unknown): boolean {
  const status = (error as { status?: number })?.status;
  return status === 429 || /RESOURCE_EXHAUSTED/.test(String((error as Error)?.message ?? error));
}
