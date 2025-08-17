const {onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const express = require("express");
const cors = require("cors");

// Define secrets for API keys
const openaiApiKey = defineSecret("OPENAI_API_KEY");
const usdaApiKey = defineSecret("USDA_API_KEY");

// Import route handlers
const scanRoutes = require("./routes/scan.route");
const usdaRoutes = require("./routes/usda.route");

// Create Express app
const app = express();

// Middleware
app.use(cors({origin: true}));
app.use(express.json({limit: "15mb"}));

// Routes
app.use("/scan", scanRoutes);
app.use("/usda", usdaRoutes);

// Health check endpoint
app.get("/", (req, res) => {
  res.json({
    message: "Cal AI Clone API is running on Firebase Functions",
    timestamp: new Date().toISOString(),
    routes: ["/scan/analyze", "/usda/search", "/usda/detail/:fdcId", "/usda/normalize"]
  });
});

// Make secrets available to routes
app.locals.openaiApiKey = openaiApiKey;
app.locals.usdaApiKey = usdaApiKey;

// Export the Express app as a Firebase Function
exports.api = onRequest({
  timeoutSeconds: 60,
  memory: "1GiB",
  cors: true,
  secrets: [openaiApiKey, usdaApiKey],
}, app);
