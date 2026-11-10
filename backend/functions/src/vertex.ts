// One Gemini client on Vertex AI in this Firebase project (billed to the project, no API key),
// made on first use and kept for later requests while the function instance stays warm.

import { GoogleGenAI } from "@google/genai";

let client: GoogleGenAI | undefined;

function projectId(): string {
  return process.env.GCLOUD_PROJECT ?? JSON.parse(process.env.FIREBASE_CONFIG ?? "{}").projectId;
}

export function vertexAI(): GoogleGenAI {
  client ??= new GoogleGenAI({ vertexai: true, project: projectId(), location: "global" });
  return client;
}
