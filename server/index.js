import "dotenv/config";
import express from "express";
import cors from "cors";
import scanRoutes from "./routes/scan.route.js";
import usdaRoutes from "./routes/usda.route.js";

const app = express();

app.use(cors());
app.use(express.json({ limit: "15mb" }));

app.use("/scan", scanRoutes);
app.use("/usda", usdaRoutes);

const port = process.env.PORT || 3000;
app.listen(port, '0.0.0.0', () => {
    console.log('Server running on http://0.0.0.0:3000');
  });