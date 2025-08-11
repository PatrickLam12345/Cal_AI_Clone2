import express from "express";
import OpenAI from "openai";

const router = express.Router();
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

router.post("/analyze", async (req, res) => {
  try {
    const { image_base64 } = req.body;
    if (!image_base64) return res.status(400).json({ error: "image_base64 required" });

    const system = `
You are a nutrition expert analyzing a meal. Identify ALL individual ingredients visible in the image.
Return ONLY JSON: {"items":[{"name":string,"portion_desc":string,"portion_grams":number}]}

Rules:
- Identify individual ingredients, not just "meal" names (e.g., "chicken breast", "brown rice", "broccoli" not just "stir fry")
- Portion grams must be your best estimate in grams for each ingredient
- portion_desc is human-friendly, e.g., "1 cup", "150 g", "1 medium piece"
- Be specific with ingredient names for USDA lookup (e.g., "chicken breast" not "chicken", "brown rice" not "rice")
- Estimate realistic portions based on what's visible
- Deduplicate by lowercased name
- 2-12 ingredients typical for a meal
- Include cooking oils, sauces, seasonings if visible
- For mixed dishes, break down into components
`;

    const userText = `Analyze this photo. Only output the strict JSON object described.`;

    const completion = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      temperature: 0.2,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: system },
        { role: "user", content: [
          { type: "text", text: userText },
          { type: "image_url", image_url: { url: `data:image/jpeg;base64,${image_base64}` } }
        ] }
      ],
      max_tokens: 600,
    });

    const data = JSON.parse(completion.choices[0].message.content);
    // extra safety: dedupe by name
    const seen = new Set();
    data.items = (data.items || []).filter(it => {
      const k = (it.name || "").toLowerCase().trim();
      if (seen.has(k)) return false; seen.add(k); return true;
    });

    res.json(data);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: "scan-analyze-failed" });
  }
});

export default router;
