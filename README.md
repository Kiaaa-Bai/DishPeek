# DishPeek

Point your phone at a menu in a language you can't read. DishPeek redraws the
whole menu in your language, right on the photo, and every dish line becomes
tappable: a photo of the dish, what it is, and a warning if it has something
you don't eat. If you can't decide, it plans a meal for your group and budget.
When you're ready, it shows the server your order in their language.

## What it does

- **Scan** — Apple Vision reads every line on the phone in about a second; the
  scan plays on the photo itself, and the redrawn menu wipes in over it.
- **Read** — the menu keeps its layout, prices stay where they were printed, and
  Peek's Pick marks the dishes this restaurant is known for. A list view shows
  every dish with a photo.
- **Avoid** — set your diet, dislikes, allergies (the EU's 14) and spice level
  once; dishes are flagged, and anything uncertain is marked as such.
- **Decide** — an AI-planned meal for 1–6 people and three budgets, each dish
  with a reason.
- **Order** — big dish names in the menu's language, each dish's line cut from
  the photo to point at, and read aloud.
- Ten languages for the app and for translation.

## How it works

| Step | Model | Output |
| --- | --- | --- |
| Read the text | Apple Vision, on device | every line and its corners |
| Understand the menu | Gemini Flash-Lite (JSON schema) | dish names, translations, prices |
| Explain the dishes | Gemini Flash-Lite | description, spice, ingredient tags |
| Redraw the menu | Gemini Flash-Lite Image, Pro as fallback | the menu in your language, aligned to the photo |
| Find photos | Wikipedia, then Brave image search + Gemini | one photo per dish, with its source |
| Plan a meal | Gemini Flash-Lite | all 18 people × budget combinations in one call |

## Layout

- `DishPeek/` — the SwiftUI app (iOS 26+, Xcode 27)
- `backend/` — Firebase: Cloud Functions (`functions/src`) and Firestore rules

## Running it

Open `DishPeek.xcodeproj` in Xcode and run it on a simulator; the app works on a
built-in sample menu without any setup.

To scan real menus, add your own `GoogleService-Info.plist` to `DishPeek/` (it is
not in this repo) and deploy `backend/` to your Firebase project. Reading and
redrawing the menu use Gemini on Vertex AI in that project (turn the Vertex AI API
on; no key needed). The Brave, Google Places and Gemini keys are Cloud Functions
secrets and never ship in the app.

Photo credits: [credits.txt](credits.txt)
