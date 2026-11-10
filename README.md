# DishPeek

Point your phone at a menu in a language you can't read, and DishPeek turns it
into a menu you can order from: every dish line on the photo becomes tappable,
with its translation, what the dish is, a photo, and a warning if it has
something you avoid.

Final project for Mobile App Development Lab (MoLab), NYU ITP, Fall 2026.

## Layout

- `DishPeek/` — the SwiftUI app (iOS 27, Xcode 27)
- `backend/` — Firebase: Cloud Functions (`functions/src`) and Firestore rules

## Running it

The app runs on a built-in sample menu without any setup.
To use the real backend, add your own `GoogleService-Info.plist` to `DishPeek/`
(it is not in this repo) and deploy `backend/` to your Firebase project.
The Gemini and Google Places keys are Cloud Functions secrets, never in the app.
Reading the menu and redrawing it use Gemini on Vertex AI in that Firebase project (no key; the
Vertex AI API must be on); the Gemini key is only for "Known for" (Gemini grounded in Google Maps).

Photo credits: [credits.txt](credits.txt)
