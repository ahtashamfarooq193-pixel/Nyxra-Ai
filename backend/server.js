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
  `You are Nyxra AI — a smart, warm, and deeply helpful AI companion. You were created by Ahtasham, an SE student (https://ahtashamfarooq.netlify.app/). Your personality is like a knowledgeable best friend: friendly, honest, and always helpful.

PERSONALITY & TONE:
- Be genuinely warm and caring. Use emojis occasionally to make replies feel lively (e.g., 😊, 🔥, ✅).
- Be conversational, not robotic. Vary your sentence length. Use simple language.
- When giving advice or ideas, be enthusiastic and encouraging.
- If someone is sad or stressed, be empathetic first, then helpful.
- Avoid one-word answers. Always give value in every reply.

LANGUAGE RULE:
- Detect the user's language automatically (English or Roman Urdu).
- Reply ONLY in the same language the user used. Do NOT mix unless the user does.
- For Roman Urdu: use natural, respectful Pakistani style (e.g., "Ji bilkul!", "Zaroor!", "Koi baat nahi 😊").
- For English: use modern, friendly tone.

GREETING RULE:
- Greet warmly only when the user greets first.
- English: "Hey! Great to see you 😊 How can I help you today?"
- Roman Urdu: "Assalam-o-Alaikum! 😊 Kaisy hain aap? Main aapki kya madad kar sakta hoon?"

STYLISH NAME GENERATOR (IMPORTANT):
- When a user asks for a stylish/fancy name or says "stylish name banao" / "name bana do":
  1. FIRST option MUST be Small Caps style: Nᴇᴏɴ, Oʟɪᴠᴇʀ, Aʜᴛᴀsʜᴀᴍ
  2. Provide 6-9 MORE styles, each on a new line.
  3. IMPORTANT: Put EACH name in its own separate triple backtick code block (```name```) so the user can copy them one by one.
  4. End with: "Kon sa style pasand aaya? 😊"

IDEA & ADVICE MODE:
- When a user asks for ideas, tips, or help, give structured, clear responses.
- Use bullet points or numbered lists for clarity.
- For coding: always use code blocks with proper syntax highlighting.
- For recipes, plans, or how-to guides: use numbered steps.

IMAGE CAPABILITIES:
- You have a powerful AI Image Engine built-in.
- When asked to draw/generate an image: be enthusiastic! Say something like "🎨 Let me create that for you right now!" or "Zaroor! Main abhi tasveer bana raha hoon! 🖼️"
- You can generate: realistic photos, anime art, paintings, logos, backgrounds, and more.
- If the user's prompt is vague, make it better automatically.

IDENTITY:
- Your name is Nyxra AI.
- You were built by Ahtasham, a talented Software Engineering student.
- If asked about yourself: be proud and friendly. Mention your capabilities.
- NEVER claim to be ChatGPT, Gemini, or any other AI.`;

function parseCsv(value) {
  return (value || "")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
}

async function callGemini(messages, imageBase64) {
  const apiKey = (process.env.GEMINI_API_KEY || "").trim();
  if (!apiKey) throw new Error("Missing GEMINI_API_KEY in backend env.");

  const model = "gemini-1.5-flash"; // High speed and efficient
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

  const contents = messages.map(msg => {
    let role = msg.role === "assistant" ? "model" : "user";
    // Gemini doesn't support "system" role in the "contents" array for simple calls easily, 
    // it's better to prepend system instruction to the first message or use systemInstruction field.
    // For simplicity, we convert system to user or model based on context.
    if (msg.role === "system") {
      role = "user"; // Or handle specifically
    }

    const parts = [];
    if (Array.isArray(msg.content)) {
      for (const part of msg.content) {
        if (part.type === "text") {
          parts.push({ text: part.text });
        } else if (part.type === "image_url") {
          const base64Match = part.image_url.url.match(/^data:(image\/[a-z]+);base64,(.+)$/);
          if (base64Match) {
            parts.push({
              inlineData: {
                mimeType: base64Match[1],
                data: base64Match[2],
              },
            });
          }
        }
      }
    } else {
      parts.push({ text: msg.content });
    }
    return { role, parts };
  });

  // Handle System Instruction properly for Gemini
  const systemMsg = messages.find(m => m.role === "system");
  const payload = {
    contents: contents.filter(c => messages[contents.indexOf(c)].role !== "system"),
    generationConfig: {
      temperature: 0.7,
      maxOutputTokens: 4096,
    }
  };

  if (systemMsg) {
    payload.systemInstruction = {
      parts: [{ text: systemMsg.content }]
    };
  }

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const details = await response.text();
    throw new Error(`Gemini error ${response.status}: ${details}`);
  }

  const data = await response.json();
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text?.trim() || "";
  if (!text) throw new Error("Empty response from Gemini.");
  return text;
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

async function callPollinationsText(messages) {
  const apiKey = (process.env.POLLINATIONS_API_KEY || "").trim();
  const model = "gemini"; // Use Gemini via Pollinations

  const response = await fetch("https://text.pollinations.ai/", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(apiKey ? { Authorization: `Bearer ${apiKey}` } : {}),
    },
    body: JSON.stringify({
      messages,
      model,
      stream: false,
    }),
  });

  if (!response.ok) {
    const details = await response.text();
    throw new Error(`Pollinations Text error ${response.status}: ${details}`);
  }

  const text = await response.text();
  return text.trim();
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
        `https://api.cloudflare.com/client/v4/accounts/${accountId}/ai/run/@cf/stabilityai/stable-diffusion-xl-base-1.0`,
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

// Enhances user prompt to produce more realistic, high-quality images
function enhanceImagePrompt(prompt) {
  const lower = prompt.toLowerCase();
  // Don't add enhancements if the user already specified a style
  const alreadyStyled = lower.includes("anime") || lower.includes("cartoon") ||
    lower.includes("illustration") || lower.includes("painting") ||
    lower.includes("sketch") || lower.includes("watercolor") || lower.includes("3d render");

  if (alreadyStyled) return prompt;

  // Add realism boosters for photorealistic output
  return `${prompt}, photorealistic, ultra detailed, 8k resolution, professional photography, sharp focus, cinematic lighting, high dynamic range`;
}

async function callPollinationsImage(prompt, model = "flux") {
  const apiKey = (process.env.POLLINATIONS_API_KEY || "").trim();
  const baseUrl = "https://image.pollinations.ai/prompt";
  const width = Number(process.env.POLLINATIONS_IMAGE_WIDTH || 1024);
  const height = Number(process.env.POLLINATIONS_IMAGE_HEIGHT || 1024);
  const seed = Math.floor(Math.random() * 999999); // Random seed for variety

  const enhancedPrompt = enhanceImagePrompt(prompt);

  const requestUrl =
    `${baseUrl}/${encodeURIComponent(enhancedPrompt)}` +
    `?model=${encodeURIComponent(model)}&width=${width}&height=${height}&seed=${seed}&nologo=true&enhance=true` +
    (apiKey ? `&token=${apiKey}` : "");

  console.log(`[Image] Using model: ${model} | Prompt: ${enhancedPrompt.substring(0, 80)}...`);

  const response = await fetch(requestUrl, {
    method: "GET",
    headers: { Accept: "image/*" },
    signal: AbortSignal.timeout(45000), // 45s timeout for image generation
  });

  if (!response.ok) {
    const details = await response.text();
    throw new Error(`Pollinations ${model} error ${response.status}: ${details}`);
  }

  const buffer = await response.arrayBuffer();
  if (buffer.byteLength < 1000) throw new Error(`${model}: Image too small, likely failed.`);
  return Buffer.from(buffer).toString("base64");
}

async function generateImageResponse(prompt) {
  const providers = [
    // Best realistic models first (Flux is state-of-the-art)
    { name: "Pollinations-Flux",          call: () => callPollinationsImage(prompt, "flux") },
    { name: "Pollinations-FluxRealism",   call: () => callPollinationsImage(prompt, "flux-realism") },
    { name: "Pollinations-FluxPro",       call: () => callPollinationsImage(prompt, "flux-pro") },
    { name: "Pollinations-Turbo",         call: () => callPollinationsImage(prompt, "turbo") },
    // Fallback
    { name: "Cloudflare",                 call: () => callCloudflareImage(prompt) },
  ];

  const failures = [];
  for (const provider of providers) {
    try {
      const imageBase64 = await provider.call();
      if (imageBase64) return imageBase64;
      failures.push(`${provider.name}: empty response`);
    } catch (error) {
      failures.push(`${provider.name}: ${error.message}`);
    }
  }

  throw new Error(`Image generation failed across providers. ${failures.join(" | ")}`);
}

async function generateResponse(messages, imageBase64) {
  const providers = [];
  
  // 1. Google Gemini (Official) - only if key is actually set
  const geminiKey = (process.env.GEMINI_API_KEY || "").trim();
  if (geminiKey) {
    providers.push({ name: "Gemini-Official", call: () => callGemini(messages, imageBase64) });
  }

  // 2. Pollinations Text (always available, even without key - it's free)
  providers.push({ name: "Pollinations-Text", call: () => callPollinationsText(messages) });

  // 3. Groq (fast & reliable)
  providers.push({ name: "Groq", call: () => callGroq(messages, imageBase64) });

  // 4. Mistral
  providers.push({ name: "Mistral", call: () => callMistral(messages) });

  // 5. Cloudflare (last resort)
  providers.push({ name: "Cloudflare", call: () => callCloudflare(messages) });

  const failures = [];
  for (const provider of providers) {
    try {
      console.log(`Trying provider: ${provider.name}...`);
      const text = await provider.call();
      if (text) {
        console.log(`Success with provider: ${provider.name}`);
        return text;
      }
      failures.push(`${provider.name}: empty response`);
    } catch (error) {
      console.warn(`Provider ${provider.name} failed: ${error.message}`);
      failures.push(`${provider.name}: ${error.message}`);
    }
  }

  throw new Error(`All providers failed: ${failures.join(" | ")}`);
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
    console.log(`Incoming message: "${userMessage}"`);
    
    // Comprehensive regex for image requests (English & Roman Urdu)
    const imageRegex = /^\/draw|^\/image|^\/gen|^\/imagine|generate\s+image|create\s+image|make\s+an\s+image|draw\s+an\s+image|image\s+of|photo\s+of|picture\s+of|draw\s+a|imagine\s+a|tasveer\s+banao|image\s+banao|pic\s+banao|draw\s+karo|tasveer\s+dikhao/i;
    
    let isImageRequest = false;
    let imagePrompt = "";

    if (imageRegex.test(lowerMsg)) {
      isImageRequest = true;
      // Extract prompt by removing the trigger word
      imagePrompt = userMessage.replace(imageRegex, "").trim();
      
      // If prompt is empty after removal (e.g. user just said "/draw"), use the original message if it's not a slash command
      if (!imagePrompt && !userMessage.startsWith("/")) {
        imagePrompt = userMessage.trim();
      }
    }

    if (isImageRequest && imagePrompt) {
      // Clean up the prompt from common filler words
      const cleanPrompt = imagePrompt
        .replace(/^(of|a|an|the)\s+/i, "")
        .trim();

      if (cleanPrompt) {
        console.log(`Image request detected. Prompt: "${cleanPrompt}"`);
        const generatedImageBase64 = await generateImageResponse(cleanPrompt);
        return res.json({ 
          text: `🎨 **Nyxra Image Engine:** Here is the image I generated for you:\n\n*"${cleanPrompt}"*`,
          generatedImage: generatedImageBase64 
        });
      }
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
