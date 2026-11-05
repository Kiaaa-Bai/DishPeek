// Finds the restaurant the user is standing in, with Google Places API (New).
// Only the place ID may be stored; rating and the rest are fetched live each time.

export type Place = {
  id: string;
  name: string;
  area: string;
  category: string;
  distanceMeters: number;
  rating: number;
  ratingCount: number;
  mapsURL?: string;
  knownForSources: Array<{ title: string; url: string }>;
};

const FIELDS = [
  "places.id",
  "places.displayName",
  "places.rating",
  "places.userRatingCount",
  "places.googleMapsUri",
  "places.primaryTypeDisplayName",
  "places.location",
  "places.addressComponents",
].join(",");

type GooglePlace = {
  id: string;
  displayName?: { text: string };
  rating?: number;
  userRatingCount?: number;
  googleMapsUri?: string;
  primaryTypeDisplayName?: { text: string };
  location?: { latitude: number; longitude: number };
  addressComponents?: Array<{ longText: string; types: string[] }>;
};

function metersBetween(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const r = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(a));
}

// The neighborhood, or the closest thing to it in this country's addresses.
function areaOf(place: GooglePlace): string {
  const order = ["neighborhood", "sublocality_level_2", "sublocality_level_1", "sublocality", "locality"];
  for (const type of order) {
    const part = place.addressComponents?.find((c) => c.types.includes(type));
    if (part) return part.longText;
  }
  return "";
}

async function search(apiKey: string, endpoint: string, body: object): Promise<GooglePlace[]> {
  const response = await fetch(`https://places.googleapis.com/v1/places:${endpoint}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": FIELDS,
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    throw new Error(`Places ${endpoint} failed: ${response.status} ${await response.text()}`);
  }
  const json = (await response.json()) as { places?: GooglePlace[] };
  return json.places ?? [];
}

// The restaurant at this spot. The name printed on the menu, when we have it, beats distance alone.
export async function findPlace(
  apiKey: string,
  latitude: number,
  longitude: number,
  languageCode: string,
  nameHint?: string,
): Promise<Place | null> {
  const center = { latitude, longitude };
  let places: GooglePlace[] = [];

  if (nameHint) {
    places = await search(apiKey, "searchText", {
      textQuery: nameHint,
      languageCode,
      maxResultCount: 5,
      locationBias: { circle: { center, radius: 300 } },
    });
  }
  // A name search comes back best match first; keep that order.
  // Without a name, the closest place is the best guess.
  const byName = places.length > 0;
  if (!byName) {
    places = await search(apiKey, "searchNearby", {
      includedTypes: ["restaurant", "cafe", "bar", "bakery"],
      maxResultCount: 10,
      rankPreference: "DISTANCE",
      languageCode,
      locationRestriction: { circle: { center, radius: 150 } },
    });
  }

  const ranked = places
    .filter((p) => p.location)
    .map((p) => ({ p, distance: metersBetween(latitude, longitude, p.location!.latitude, p.location!.longitude) }))
    .filter((x) => x.distance < 500);
  if (!byName) {
    ranked.sort((a, b) => a.distance - b.distance);
  }

  const best = ranked[0];
  if (!best) return null;

  return {
    id: best.p.id,
    name: best.p.displayName?.text ?? "",
    area: areaOf(best.p),
    category: best.p.primaryTypeDisplayName?.text ?? "",
    distanceMeters: Math.round(best.distance),
    rating: best.p.rating ?? 0,
    ratingCount: best.p.userRatingCount ?? 0,
    mapsURL: best.p.googleMapsUri,
    knownForSources: [],
  };
}
