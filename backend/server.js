const path = require("path");
require("dotenv").config({
  path: path.join(__dirname, ".env"),
  override: true,
});
const express = require("express");
const cors = require("cors");

const app = express();
app.use(cors());
app.use(express.json({ limit: "8mb" }));

const SYSTEM_INSTRUCTION =
  'You are Nyxra AI, a highly intelligent, professional, and friendly AI assistant. ' +
  'LANGUAGE RULE (STRICT):\n' +
  '- If the user speaks in English, you MUST reply ONLY in English.\n' +
  '- If the user speaks in Roman Urdu, you MUST reply ONLY in Roman Urdu.\n' +
  '- DO NOT mix languages unless specifically asked.\n\n' +
  'GREETING RULE:\n' +
  '- Only greet at the start of a conversation or if the user greets you.\n' +
  '- Use "Assalam-o-Alaikum" for Roman Urdu users and "Hello/Hi" for English users.\n' +
  '- In ongoing chat, skip the greeting and answer directly.\n\n' +
  'STRICT TOKEN RULES:\n' +
  '- Daily limit: 5000 tokens. Do not mention this unless asked.\n\n' +
  'IDENTITY:\n' +
  '- Developed by "Ahtasham", an SE student: https://ahtashamfarooq.netlify.app/\n' +
  '- Tone: Professional, helpful, and concise.';

function parseCsv(value) {
  return (value || "")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function buildMessages(userMessage, conversationHistory, imageBase64) {
  const messages = [{ role: "system", content: SYSTEM_INSTRUCTION }];
  const history = Array.isArray(conversationHistory) ? conversationHistory.slice(-10) : [];

  for (const item of history) {
    if (!item || typeof item.text !== "string") continue;
    messages.push({
      role: item.isUser ? "user" : "assistant",
      content: item.text,
    });
  }

  if (imageBase64) {
    messages.push({
      role: "user",
      content: [
        { type: "text", text: userMessage || "Analyze this image." },
        {
          type: "image_url",
          image_url: { url: `data:image/jpeg;base64,${imageBase64}` },
        },
      ],
    });
  } else {
    messages.push({ role: "user", content: userMessage });
  }

  return messages;
}

async function callGroq(messages, imageBase64) {
  const keys = parseCsv(process.env.GROQ_API_KEYS);
  if (!keys.length) throw new Error("Missing GROQ_API_KEYS in backend env.");

  const baseUrl = (process.env.GROQ_BASE_URL || "https://api.groq.com/openai/v1").trim();
  const model = (process.env.GROQ_MODEL || "llama-3.3-70b-versatile").trim();
  const requestModel = imageBase64 ? "llama-3.2-11b-vision-preview" : model;

  const failures = [];
  for (const key of keys) {
    const response = await fetch(`${baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({
        model: requestModel,
        messages,
        max_tokens: 4096,
        temperature: 0.7,
        stream: false,
      }),
    });

    if (response.status === 429) {
      failures.push("rate_limited");
      continue;
    }
    if (!response.ok) {
      const details = await response.text();
      failures.push(`Groq error ${response.status}: ${details}`);
      continue;
    }

    const data = await response.json();
    const text = data.choices?.[0]?.message?.content?.trim() || "";
    if (text) return text;
    failures.push("empty_response");
  }

  throw new Error(`All GROQ keys failed. ${failures.join(" | ")}`);
}

async function callMistral(messages) {
  const keys = parseCsv(process.env.MISTRAL_API_KEYS);
  if (!keys.length) throw new Error("Mistral keys not configured.");

  const model = (process.env.MISTRAL_MODEL || "open-mistral-7b").trim();

  const failures = [];
  for (const key of keys) {
    const response = await fetch("https://api.mistral.ai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({
        model,
        messages,
        stream: false,
      }),
    });

    if (response.status === 429) {
      failures.push("rate_limited");
      continue;
    }
    if (!response.ok) {
      const details = await response.text();
      failures.push(`Mistral error ${response.status}: ${details}`);
      continue;
    }

    const data = await response.json();
    const text = data.choices?.[0]?.message?.content?.trim() || "";
    if (text) return text;
    failures.push("empty_response");
  }

  throw new Error(`All Mistral keys failed. ${failures.join(" | ")}`);
}

async function callCloudflare(messages) {
  const tokens = parseCsv(process.env.CLOUDFLARE_TOKEN);
  const accountId = (process.env.CLOUDFLARE_ACCOUNT_ID || "").trim();
  if (!tokens.length || !accountId) throw new Error("Cloudflare fallback not configured.");

  const failures = [];
  for (const token of tokens) {
    try {
      const response = await fetch(
        `https://api.cloudflare.com/client/v4/accounts/${accountId}/ai/v1/chat/completions`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({
            model: "@cf/meta/llama-3-8b-instruct",
            messages,
            stream: false,
          }),
        }
      );

      if (response.status === 429) {
        failures.push("rate_limited");
        continue;
      }
      if (!response.ok) {
        const details = await response.text();
        failures.push(`Cloudflare error ${response.status}: ${details}`);
        continue;
      }

      const data = await response.json();
      const text = data.result?.response?.trim() || data.choices?.[0]?.message?.content?.trim() || "";
      if (text) return text;
    } catch (e) {
      failures.push(`Fetch error: ${e.message}`);
    }
  }
  throw new Error(`All Cloudflare tokens failed. ${failures.join(" | ")}`);
}

async function callCloudflareImage(prompt) {
  const tokens = parseCsv(process.env.CLOUDFLARE_TOKEN);
  const accountId = (process.env.CLOUDFLARE_ACCOUNT_ID || "").trim();
  if (!tokens.length || !accountId) throw new Error("Cloudflare image service not configured.");

  const failures = [];
  for (const token of tokens) {
    try {
      const response = await fetch(
        `https://api.cloudflare.com/client/v4/accounts/${accountId}/ai/v1/models/@cf/stabilityai/stable-diffusion-xl-base-1.0`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ prompt }),
        }
      );

      if (response.status === 429) {
        failures.push("rate_limited");
        continue;
      }
      if (!response.ok) {
        const details = await response.text();
        failures.push(`Cloudflare Image error ${response.status}: ${details}`);
        continue;
      }

      const buffer = await response.arrayBuffer();
      return Buffer.from(buffer).toString("base64");
    } catch (e) {
      failures.push(`Fetch error: ${e.message}`);
    }
  }
  throw new Error(`Image generation failed. ${failures.join(" | ")}`);
}

async function generateResponse(messages, imageBase64) {
  const providers = [
    { name: "Groq", call: () => callGroq(messages, imageBase64) },
    { name: "Mistral", call: () => callMistral(messages) },
    { name: "Cloudflare", call: () => callCloudflare(messages) },
  ];

  const failures = [];
  for (const provider of providers) {
    try {
      const text = await provider.call();
      if (text) return text;
      failures.push(`${provider.name}: empty response`);
    } catch (error) {
      failures.push(`${provider.name}: ${error.message}`);
    }
  }

  throw new Error(failures.join(" | "));
}

app.get("/health", (_req, res) => {
  res.json({ ok: true, service: "nyxra-backend" });
});

app.post("/api/chat", async (req, res) => {
  try {
    const userMessage = typeof req.body?.userMessage === "string" ? req.body.userMessage.trim() : "";
    const conversationHistory = req.body?.conversationHistory || [];
    const imageBase64 = typeof req.body?.imageBase64 === "string" ? req.body.imageBase64.trim() : "";

    if (!userMessage && !imageBase64) {
      return res.status(400).json({ error: "Message or image is required." });
    }

    // Check if it's an image generation request
    const lowerMsg = userMessage.toLowerCase();
    const imageKeywords = ["/draw", "generate image", "create image", "make an image", "draw an image", "generate an image"];
    
    let isImageRequest = false;
    let imagePrompt = "";

    for (const keyword of imageKeywords) {
      if (lowerMsg.startsWith(keyword)) {
        isImageRequest = true;
        imagePrompt = userMessage.substring(keyword.length).trim();
        if (imagePrompt.startsWith("of ")) imagePrompt = imagePrompt.substring(3).trim();
        break;
      }
    }

    if (isImageRequest && imagePrompt) {
      const generatedImageBase64 = await callCloudflareImage(imagePrompt);
      return res.json({ 
        text: `🎨 **Generated Image:** Here is what I created for: "${imagePrompt}"`,
        generatedImage: generatedImageBase64 
      });
    }

    const messages = buildMessages(userMessage, conversationHistory, imageBase64);
    const text = await generateResponse(messages, imageBase64);
    return res.json({ text });
  } catch (error) {
    console.error("POST /api/chat failed:", error.message);
    const errorMessage = error.message || "AI service is temporarily unavailable.";
    return res.status(500).json({ 
      error: "Server Error", 
      details: errorMessage.includes("failed") ? "All AI providers are currently busy. Please try again in a few seconds." : errorMessage
    });
  }
});

const port = Number(process.env.PORT || 8080);
if (!process.env.VERCEL) {
  app.listen(port, () => {
    console.log(`Nyxra backend running on port ${port}`);
  });
}

module.exports = app;
