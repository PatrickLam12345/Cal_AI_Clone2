import express from "express";
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
    const foundation = await searchRaw(q, { page, dataType: "Foundation", pageSize, sortBy: "relevance",
    });
    let foods = Array.isArray(foundation.foods) ? foundation.foods : [];
    let totalHits =
      typeof foundation.totalHits === "number" ? foundation.totalHits : (foods.length || 0);

    // Fallback to SR Legacy if Foundation empty
    if (foods.length === 0) {
      const legacy = await searchRaw(q, { page, dataType: "SR Legacy", pageSize, sortBy: "relevance" });
      foods = Array.isArray(legacy.foods) ? legacy.foods : [];
      totalHits =
        typeof legacy.totalHits === "number" ? legacy.totalHits : (foods.length || 0);
    }

    const compact = foods.map((f) => {
      const { calories, per } = listRowCaloriesAndPer(f);
      const unitText = servingTextForDisplay(f, per);
      return {
        fdcId: f?.fdcId,
        name: String(f?.description || "Unknown"),
        calories,
        unit: unitText,
        dataType: f?.dataType || "",
        brandName: f?.brandName || null,
        gtinUpc: f?.gtinUpc || null,
      };
    });

    // Sort results to prioritize exact matches and better relevance
    const sortedFoods = compact.sort((a, b) => {
      const queryLower = q.toLowerCase();
      const aNameLower = a.name.toLowerCase();
      const bNameLower = b.name.toLowerCase();
      
      // Exact match gets highest priority
      const aExact = aNameLower === queryLower;
      const bExact = bNameLower === queryLower;
      if (aExact && !bExact) return -1;
      if (!aExact && bExact) return 1;
      
      // Starts with query gets second priority
      const aStartsWith = aNameLower.startsWith(queryLower);
      const bStartsWith = bNameLower.startsWith(queryLower);
      if (aStartsWith && !bStartsWith) return -1;
      if (!aStartsWith && bStartsWith) return 1;
      
      // Contains query gets third priority
      const aContains = aNameLower.includes(queryLower);
      const bContains = bNameLower.includes(queryLower);
      if (aContains && !bContains) return -1;
      if (!aContains && bContains) return 1;
      
      // If both have same match level, sort alphabetically
      return aNameLower.localeCompare(bNameLower);
    });

    res.json({ foods: sortedFoods, page, pageSize, totalHits });
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

async function searchRaw(query, { page = 1, dataType, pageSize = 25, sortBy } = {}) {
  const url = new URL(`${BASE}/foods/search`);
  url.searchParams.set("api_key", USDA_API_KEY);
  url.searchParams.set("query", query);
  url.searchParams.set("pageNumber", String(page));
  url.searchParams.set("pageSize", String(pageSize));
  if (dataType) url.searchParams.set("dataType", dataType);
  if (sortBy) url.searchParams.set("sortBy", sortBy);

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

/* -------- Robust energy + serving extraction across datasets -------- */

function readNutrient(n) {
  return {
    id: n?.nutrient?.id ?? n?.nutrientId ?? null,
    num: (n?.nutrient?.number ?? n?.nutrientNumber ?? "").toString(),
    name: (n?.nutrient?.name ?? n?.nutrientName ?? "").toString().toLowerCase(),
    unit: (n?.nutrient?.unitName ?? n?.unitName ?? "").toString().toLowerCase(),
    val:
      typeof n?.amount === "number"
        ? n.amount
        : typeof n?.value === "number"
        ? n.value
        : null,
  };
}

function getNutrientVal(f, matcher) {
  const arr = Array.isArray(f?.foodNutrients) ? f.foodNutrients : [];
  for (const n of arr) {
    const r = readNutrient(n);
    if (matcher(r)) return r.val;
  }
  return null;
}

// kcal direct if present, else 0
function energyKcalFromAny(f) {
  // id 1008 (Energy kcal)
  let v = getNutrientVal(f, (r) => r.id === 1008 && typeof r.val === "number" && r.val > 0);
  if (typeof v === "number") return v;

  // legacy number "208"
  v = getNutrientVal(f, (r) => r.num === "208" && typeof r.val === "number" && r.val > 0);
  if (typeof v === "number") return v;

  // name/unit "energy"/"kcal"
  v = getNutrientVal(f, (r) => r.name === "energy" && r.unit === "kcal" && typeof r.val === "number" && r.val > 0);
  if (typeof v === "number") return v;

  // kJ → kcal
  v = getNutrientVal(f, (r) => r.name === "energy" && r.unit === "kj" && typeof r.val === "number" && r.val > 0);
  if (typeof v === "number") return v / 4.184;

  return 0;
}

// Compute kcal from macros (general Atwater): 4/9/4/7
function energyKcalFromMacros(f) {
  const arr = Array.isArray(f?.foodNutrients) ? f.foodNutrients : [];
  if (!arr.length) return 0;

  const by = (pred) => {
    const v = getNutrientVal(f, pred);
    return typeof v === "number" ? v : null;
  };

  // Protein (g): id 1003, number "203", name "protein"
  let protein = by((r) => r.id === 1003 || r.num === "203" || r.name === "protein");
  // If Protein missing, infer from Nitrogen (id 1002, number "202") × 6.25
  if (protein == null) {
    const nitrogen = by((r) => r.id === 1002 || r.num === "202" || r.name === "nitrogen");
    if (typeof nitrogen === "number") protein = nitrogen * 6.25;
  }

  // Total fat (g): id 1004 or "total fat (nlea)" id 1085/number "298"
  let fat = by((r) => r.id === 1004 || r.num === "204" || r.name === "total lipid (fat)" || r.name === "total fat (nlea)");
  if (fat == null) {
    fat = by((r) => r.id === 1085 || r.num === "298"); // NLEA
  }

  // Carbohydrate by difference (g): id 1005 / number "205"
  const carbs = by((r) => r.id === 1005 || r.num === "205" || r.name === "carbohydrate, by difference");

  // Alcohol (g): id 1006 / number "221"
  const alcohol = by((r) => r.id === 1006 || r.num === "221" || r.name === "alcohol, ethyl");

  // If we don't have at least fat+carb+protein (or any two), skip
  const p = typeof protein === "number" ? protein : 0;
  const fval = typeof fat === "number" ? fat : 0;
  const c = typeof carbs === "number" ? carbs : 0;
  const alc = typeof alcohol === "number" ? alcohol : 0;

  const haveAny = p > 0 || fval > 0 || c > 0 || alc > 0;
  if (!haveAny) return 0;

  const kcal = (p * 4) + (fval * 9) + (c * 4) + (alc * 7);
  return Math.round(kcal);
}

// Decide row calories + what they are "per"
function listRowCaloriesAndPer(f) {
  // Branded → labelNutrients per serving
  const ln = f?.labelNutrients;
  const labelCals = ln?.calories?.value;
  if (typeof labelCals === "number" && labelCals > 0) {
    const size = Number(f?.servingSize);
    const unit = String(f?.servingSizeUnit || "").trim();
    const per = Number.isFinite(size) && size > 0 ? `${cleanNum(size)} ${unit || ""}`.trim() : "serving";
    return { calories: Math.round(labelCals), per };
  }

  // Foundation/SR → prefer direct energy; else compute from macros
  let energyPer100g = energyKcalFromAny(f);
  if (energyPer100g <= 0) {
    energyPer100g = energyKcalFromMacros(f);
  }

  const size = Number(f?.servingSize);
  const unit = String(f?.servingSizeUnit || "").trim().toLowerCase();

  if (energyPer100g > 0 && Number.isFinite(size) && size > 0 && unit === "g") {
    return { calories: Math.round(energyPer100g * (size / 100)), per: `${cleanNum(size)} g` };
  }

  if (energyPer100g > 0) return { calories: Math.round(energyPer100g), per: "100 g" };

  // Unknown energy — still default per to 100 g for non-branded display
  return { calories: 0, per: "100 g" };
}

function servingTextForDisplay(f, fallbackPer) {
  try {
    const size = Number(f?.servingSize);
    const unit = String(f?.servingSizeUnit || "").trim();
    if (Number.isFinite(size) && size > 0) {
      return unit ? `${cleanNum(size)} ${unit}` : `${cleanNum(size)}`;
    }
    const t = String(f?.householdServingFullText || "").trim();
    if (t) return t;
    const p0 = Array.isArray(f?.foodPortions) ? f.foodPortions[0] : null;
    if (p0?.gramWeight) return `${cleanNum(p0.gramWeight)} g`;
    return fallbackPer || "100 g"; // sensible default for Foundation/SR
  } catch {
    return fallbackPer || "100 g";
  }
}

function cleanNum(n) {
  return Number.isInteger(n) ? String(n) : Number(n).toFixed(1);
}

/* ---------------------- Normalize detail → table rows ---------------------- */

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
      const v = val && typeof val === "object" && typeof val.value === "number" ? val.value : null;
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
