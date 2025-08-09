// server/routes/usda.route.js
import express from "express";
// If Node < 18, uncomment to polyfill fetch:
// import fetch from "node-fetch";

const router = express.Router();
const USDA_API_KEY = process.env.USDA_API_KEY;
const BASE = "https://api.nal.usda.gov/fdc/v1";

/* ---------------------------------- Routes ---------------------------------- */

// GET /usda/search?q=chicken&page=1
router.get("/search", async (req, res) => {
  try {
    const q = String(req.query.q || "").trim();
    const page = parseInt(String(req.query.page || "1"), 10);
    const pageSize = 25;
    if (!q) return res.json({ foods: [], page: 1, pageSize, totalHits: 0 });

    // Try Foundation first
    const foundation = await searchRaw(q, { page, dataType: "Foundation", pageSize });
    let foods = Array.isArray(foundation.foods) ? foundation.foods : [];
    let totalHits =
      typeof foundation.totalHits === "number" ? foundation.totalHits : (foods.length || 0);

    // Fallback to SR Legacy if Foundation empty
    if (foods.length === 0) {
      const legacy = await searchRaw(q, { page, dataType: "SR Legacy", pageSize });
      foods = Array.isArray(legacy.foods) ? legacy.foods : [];
      totalHits =
        typeof legacy.totalHits === "number" ? legacy.totalHits : (foods.length || 0);
    }

    // Map to compact shape (matches your original client)
    const compact = foods.map((f) => {
      const { calories } = safeCaloriesForListRow(f);
      const unitText = safeServingText(f);
      return {
        fdcId: f?.fdcId,
        name: String(f?.description || "Unknown"),
        calories,        // per serving when we can compute, else per 100 g or 0
        unit: unitText,  // "150 g", "1 cup", or "serving"
        dataType: f?.dataType || "",
        brandName: f?.brandName || null,
        gtinUpc: f?.gtinUpc || null,
      };
    });

    res.json({ foods: compact, page, pageSize, totalHits });
  } catch (e) {
    console.error("[/usda/search] error:", e);
    res.status(500).json({ error: "usda-search-failed" });
  }
});

// GET /usda/detail/:fdcId
router.get("/detail/:fdcId", async (req, res) => {
  try {
    const fdcId = parseInt(req.params.fdcId, 10);
    if (!fdcId) return res.status(400).json({ error: "invalid fdcId" });
    const detail = await getDetail(fdcId);
    res.json(detail);
  } catch (e) {
    console.error("[/usda/detail] error:", e);
    res.status(500).json({ error: "usda-detail-failed" });
  }
});

// POST /usda/normalize  { detail: <raw USDA JSON> }
router.post("/normalize", async (req, res) => {
  try {
    const detail = req.body?.detail;
    if (!detail || typeof detail !== "object") {
      return res.status(400).json({ error: "detail object required" });
    }
    const nutrients = normalizedNutrients(detail);
    res.json({ nutrients });
  } catch (e) {
    console.error("[/usda/normalize] error:", e);
    res.status(500).json({ error: "usda-normalize-failed" });
  }
});

export default router;

/* --------------------------------- Helpers --------------------------------- */

async function fetchJson(url, opts = {}, ms = 8000) {
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), ms);
  try {
    const r = await fetch(url, { ...opts, signal: ac.signal });
    return r;
  } finally {
    clearTimeout(t);
  }
}

async function searchRaw(query, { page = 1, dataType, pageSize = 25 } = {}) {
  const url = new URL(`${BASE}/foods/search`);
  url.searchParams.set("api_key", USDA_API_KEY);
  url.searchParams.set("query", query);
  url.searchParams.set("pageNumber", String(page));
  url.searchParams.set("pageSize", String(pageSize));
  if (dataType) url.searchParams.set("dataType", dataType);

  const r = await fetchJson(url);
  if (!r.ok) throw new Error(`USDA search failed: ${r.status}`);
  return r.json();
}

async function getDetail(fdcId) {
  const url = `${BASE}/food/${fdcId}?api_key=${USDA_API_KEY}`;
  const r = await fetchJson(url);
  if (!r.ok) throw new Error("detail failed");
  return r.json();
}

// Pull "Energy" from search item; handle kcal or kJ
function energyFromSearchItemKcal(f) {
  const arr = Array.isArray(f?.foodNutrients) ? f.foodNutrients : [];
  const kcalHit = arr.find((n) => {
    const name = (n?.nutrientName || n?.nutrient?.name || "").toLowerCase();
    const unit = (n?.unitName || n?.nutrient?.unitName || "").toLowerCase();
    return name === "energy" && unit === "kcal";
  });
  if (typeof kcalHit?.value === "number") return kcalHit.value;
  if (typeof kcalHit?.amount === "number") return kcalHit.amount;

  const kjHit = arr.find((n) => {
    const name = (n?.nutrientName || n?.nutrient?.name || "").toLowerCase();
    const unit = (n?.unitName || n?.nutrient?.unitName || "").toLowerCase();
    return name === "energy" && unit === "kj";
  });
  const v =
    typeof kjHit?.value === "number"
      ? kjHit.value
      : typeof kjHit?.amount === "number"
      ? kjHit.amount
      : null;
  if (typeof v === "number" && v > 0) return v / 4.184;
  return 0;
}

// Best-effort calories for list row
function safeCaloriesForListRow(f) {
  try {
    const ln = f?.labelNutrients;
    const labelCals = ln?.calories?.value;
    if (typeof labelCals === "number" && labelCals > 0) {
      return { calories: Math.round(labelCals) }; // Branded per serving
    }

    const energyPer100g = energyFromSearchItemKcal(f); // Foundation/SR per 100 g
    const size = Number(f?.servingSize);
    const unit = String(f?.servingSizeUnit || "").toLowerCase();

    if (energyPer100g > 0 && size > 0 && unit === "g") {
      return { calories: Math.round(energyPer100g * (size / 100)) };
    }

    if (energyPer100g > 0) return { calories: Math.round(energyPer100g) };
    return { calories: 0 };
  } catch {
    return { calories: 0 };
  }
}

// Human-friendly serving text; falls back to "serving"
function safeServingText(f) {
  try {
    const sizeRaw = f?.servingSize;
    const unit = String(f?.servingSizeUnit || "").trim();
    const size = typeof sizeRaw === "number" ? sizeRaw : Number(sizeRaw);
    if (Number.isFinite(size) && size > 0) {
      const sizeStr = Number.isInteger(size) ? String(size) : size.toFixed(1);
      return unit ? `${sizeStr} ${unit}` : sizeStr;
    }
    if (f?.householdServingFullText) {
      const t = String(f.householdServingFullText).trim();
      if (t) return t;
    }
    const p0 = Array.isArray(f?.foodPortions) ? f.foodPortions[0] : null;
    if (p0?.gramWeight) return `${p0.gramWeight} g`;
    return unit || "serving";
  } catch {
    return "serving";
  }
}

// Normalize nutrients (detail + labelNutrients) → [{name,value,unit}]
function normalizedNutrients(detail = {}) {
  const out = [];

  const fn = Array.isArray(detail.foodNutrients) ? detail.foodNutrients : [];
  for (const raw of fn) {
    if (!raw || typeof raw !== "object") continue;
    const name = raw.nutrientName || raw?.nutrient?.name || null;
    const unit = raw.unitName || raw?.nutrient?.unitName || "";
    let val =
      typeof raw.amount === "number"
        ? raw.amount
        : typeof raw.value === "number"
        ? raw.value
        : null;

    // convert Energy kJ→kcal for consistency
    const nm = (name || "").toLowerCase();
    const un = (unit || "").toLowerCase();
    if (nm === "energy" && un === "kj" && typeof val === "number") {
      val = val / 4.184;
    }

    if (typeof name === "string" && typeof val === "number") {
      out.push({ name, value: Number(val), unit: un === "kj" ? "kcal" : String(unit || "") });
    }
  }

  const ln = detail?.labelNutrients;
  if (ln && typeof ln === "object") {
    const keyToName = {
      calories: "Energy",
      totalFat: "Total lipid (fat)",
      saturatedFat: "Fatty acids, total saturated",
      transFat: "Fatty acids, total trans",
      cholesterol: "Cholesterol",
      sodium: "Sodium, Na",
      totalCarbohydrate: "Carbohydrate, by difference",
      dietaryFiber: "Fiber, total dietary",
      totalSugars: "Sugars, total",
      addedSugars: "Added sugars",
      protein: "Protein",
      vitaminD: "Vitamin D",
      calcium: "Calcium, Ca",
      iron: "Iron, Fe",
      potassium: "Potassium, K",
    };
    const units = {
      calories: "kcal",
      totalFat: "g",
      saturatedFat: "g",
      transFat: "g",
      cholesterol: "mg",
      sodium: "mg",
      totalCarbohydrate: "g",
      dietaryFiber: "g",
      totalSugars: "g",
      addedSugars: "g",
      protein: "g",
      vitaminD: "mcg",
      calcium: "mg",
      iron: "mg",
      potassium: "mg",
    };
    for (const [key, val] of Object.entries(ln)) {
      if (!keyToName[key]) continue;
      const v =
        val && typeof val === "object" && typeof val.value === "number"
          ? val.value
          : null;
      if (v == null) continue;
      out.push({
        name: keyToName[key],
        value: Number(v),
        unit: units[key] || "",
      });
    }
  }

  const dedup = new Map();
  for (const n of out) {
    const k = String(n.name).trim();
    if (!dedup.has(k)) {
      dedup.set(k, n);
    } else {
      const old = dedup.get(k);
      if ((Number(old.value) || 0) === 0 && (Number(n.value) || 0) !== 0) {
        dedup.set(k, n);
      }
    }
  }

  return Array.from(dedup.values()).sort((a, b) =>
    String(a.name).localeCompare(String(b.name))
  );
}
