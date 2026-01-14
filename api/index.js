require("dotenv").config();
const express = require("express");
const cors = require("cors");
const connectWithDB = require("./config/db");
const cookieSession = require("cookie-session");
const cookieParser = require("cookie-parser");
const cloudinary = require("cloudinary").v2;

// connect with database
connectWithDB();

// cloudinary configuration
cloudinary.config({
  cloud_name: process.env.CLOUDINARY_NAME,
  api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET,
});

const app = express();

// Behind a LoadBalancer/ingress we need this so secure cookies work when TLS is terminated upstream
app.set("trust proxy", 1);

// For handling cookies
app.use(cookieParser());

// Initialize cookie-session middleware
const cookieSecure = process.env.COOKIE_SECURE !== "false"; // default secure=true unless explicitly disabled
const cookieSameSite = process.env.COOKIE_SAMESITE || (cookieSecure ? "none" : "lax");
const allowedOrigins = (process.env.ALLOWED_ORIGINS || process.env.CLIENT_URL || "")
  .split(",")
  .map((o) => o.trim())
  .filter(Boolean);

app.use(
  cookieSession({
    name: "session",
    maxAge: Number(process.env.COOKIE_TIME || 7) * 24 * 60 * 60 * 1000,
    keys: [process.env.SESSION_SECRET],
    secure: cookieSecure,
    sameSite: cookieSameSite,
    httpOnly: true,
  })
);

// middleware to handle json
app.use(express.json());

// CORS
app.use(
  cors({
    origin: (origin, callback) => {
      // Debug logging
      console.log('CORS check - Origin:', origin, 'Allowed:', allowedOrigins);
      // Allow requests with no origin (same-origin via proxy, mobile apps, curl)
      // or if origin is in the allowlist
      if (!origin || allowedOrigins.includes(origin)) {
        console.log('CORS check - ALLOWED');
        return callback(null, true);
      }
      return callback(new Error(`CORS: Origin '${origin}' not allowed. Allowed: ${allowedOrigins.join(', ')}`));
    },
    credentials: true,
  })
);

// use express router
app.use("/", require("./routes"));

app.listen(process.env.PORT || 8000, (err) => {
  if (err) {
    console.log("Error in connecting to server: ", err);
  }
  console.log(`Server is running on port no. ${process.env.PORT}`);
});

module.exports = app;
