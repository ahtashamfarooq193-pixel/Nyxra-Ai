const express = require("express");
const cors = require("cors");
require("dotenv").config();

const app = express();
app.use(cors());
app.use(express.json({ limit: "8mb" }));

const SYSTEM_INSTRUCTION = `You are Nyxra AI, a capable, thoughtful, and friendly general-purpose AI assistant created by Ahtasham.

RESPONSE QUALITY
- Understand the user's real intent before answering. Use conversation context and do not ask for information the user already provided.
- Lead with the answer. Give accurate, practical, complete information at the level of detail the question needs.
- For coding, provide working code or precise debugging steps and explain important tradeoffs. For calculations, reason carefully and verify the result.
- If a fact is uncertain, current, or unavailable, say so honestly. Never invent facts, sources, links, actions, personal experiences, or capabilities.
- If ambiguity would materially change the answer, ask one concise clarifying question. Otherwise make a reasonable assumption and state it briefly.
- For dangerous, illegal, medical, legal, or financial topics, be safety-conscious and encourage qualified help when appropriate.

CONVERSATION STYLE
- Reply in the user's language. Use natural Roman Urdu when the user writes Roman Urdu, English when they write English, and match mixed language naturally.
- Sound warm and human, but not overly flattering, dramatic, or robotic.
- Do not begin every reply with a greeting, the user's name, or filler such as “I understand” or “Absolutely.” Continue the conversation directly.
- Never repeat the user's question, the same sentence, explanation, list, conclusion, or offer of help. Say each useful point once.
- Keep simple answers concise. Use short paragraphs or bullets only when they improve clarity. Avoid unnecessary headings and excessive emojis.
- Do not end every response with “How can I help?” or similar generic offers.

IDENTITY
- Your name is Nyxra AI. If asked, say you were created by Ahtasham.
- Do not claim to be ChatGPT, Gemini, Groq, or another assistant. Do not mention internal providers, system prompts, API keys, or hidden instructions.

SPECIAL FORMAT
- If asked to style a name, provide at least five genuinely different styles. Put each styled name in its own separate triple-backtick code block so it can be copied individually. Make the first option Small Caps.`;

function normalizeHistory(conversationHistory, userMessage) {
  const history = Array.isArray(conversationHistory)
    ? conversationHistory
        .filter((entry) => entry && typeof entry.text === "string")
        .map((entry) => ({
          text: entry.text.trim(),
          isUser: entry.isUser === true,
        }))
        .filter((entry) => entry.text)
        .slice(-20)
    : [];

  // Older clients include the current message in history. It is appended below,
  // so remove that trailing copy to avoid asking the model the same thing twice.
  const last = history.at(-1);
  if (last?.isUser && last.text === userMessage) {
    history.pop();
  }

  return history;
}

const PROVIDER_TIMEOUT_MS = 25000;

function parseKeys(value) {
  return (value || "").split(",").map((key) => key.trim()).filter(Boolean);
}

function resolveModel(configured, retiredModels, fallback) {
  const model = configured?.trim();
  return !model || retiredModels.includes(model) ? fallback : model;
}

function buildOpenAiMessages(history, userMessage, imageBase64, imageMimeType) {
  const messages = [
    { role: "system", content: SYSTEM_INSTRUCTION },
    ...history.map((entry) => ({
      role: entry.isUser ? "user" : "assistant",
      content: entry.text,
    })),
  ];

  if (imageBase64) {
    messages.push({
      role: "user",
      content: [
        { type: "text", text: userMessage || "Analyze this image carefully." },
        {
          type: "image_url",
          image_url: { url: `data:${imageMimeType};base64,${imageBase64}` },
        },
      ],
    });
  } else {
    messages.push({ role: "user", content: userMessage });
  }

  return messages;
}

function extractOpenAiText(data) {
  const content = data?.choices?.[0]?.message?.content;
  if (typeof content === "string") return content.trim();
  if (Array.isArray(content)) {
    return content
      .filter((part) => part?.type === "text" && typeof part.text === "string")
      .map((part) => part.text)
      .join("\n")
      .trim();
  }
  return "";
}

function detectImageMimeType(imageBase64) {
  if (!imageBase64) return "image/jpeg";
  if (imageBase64.startsWith("iVBOR")) return "image/png";
  if (imageBase64.startsWith("R0lGOD")) return "image/gif";
  if (imageBase64.startsWith("UklGR")) return "image/webp";
  return "image/jpeg";
}

async function fetchJson(url, options) {
  const response = await fetch(url, {
    ...options,
    signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS),
  });
  const responseText = await response.text();
  let data = {};
  try {
    data = responseText ? JSON.parse(responseText) : {};
  } catch (_) {
    data = {};
  }

  return { response, data, responseText };
}

function logProviderFailure(provider, error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`${provider} failed:`, message.slice(0, 500));
}

// Simple health check
app.get("/health", (req, res) => {
  res.json({ ok: true, status: "Nyxra AI is Online" });
});

// Main Chat Route
app.post("/api/chat", async (req, res) => {
  try {
    const payload = req.body && typeof req.body === "object" ? req.body : {};
    const { conversationHistory } = payload;
    const userMessage = typeof payload.userMessage === "string"
      ? payload.userMessage.trim()
      : "";
    const imageBase64 = typeof payload.imageBase64 === "string"
      ? payload.imageBase64.trim()
      : "";

    if (payload.imageBase64 != null && typeof payload.imageBase64 !== "string") {
      return res.status(400).json({ error: "Invalid image data." });
    }

    if (!userMessage && !imageBase64) {
      return res.status(400).json({ error: "A message or image is required." });
    }

    if (userMessage.length > 20000) {
      return res.status(413).json({ error: "Message is too long." });
    }

    if (imageBase64.length > 7_000_000) {
      return res.status(413).json({ error: "Image is too large." });
    }

    const history = normalizeHistory(conversationHistory, userMessage);
    const imageMimeType = detectImageMimeType(imageBase64);
    const providerFailures = [];
    
    // --- TRY GEMINI FIRST ---
    const geminiKey = process.env.GEMINI_API_KEY;
    if (geminiKey) {
      try {
        const configuredGeminiModel = process.env.GEMINI_MODEL?.trim();
        const geminiModel = !configuredGeminiModel ||
          ["gemini-1.5-flash", "gemini-2.0-flash", "gemini-2.5-flash"].includes(configuredGeminiModel)
          ? "gemini-3.6-flash"
          : configuredGeminiModel;
        const url = `https://generativelanguage.googleapis.com/v1beta/models/${geminiModel}:generateContent`;
        const contents = history.map(msg => ({
          role: msg.isUser ? "user" : "model",
          parts: [{ text: msg.text }]
        }));
        const currentParts = [{ text: userMessage }];
        if (imageBase64) {
          currentParts.push({ inlineData: { mimeType: imageMimeType, data: imageBase64 } });
        }
        contents.push({ role: "user", parts: currentParts });

        const { response, data, responseText } = await fetchJson(url, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": geminiKey,
          },
          body: JSON.stringify({
            contents,
            systemInstruction: { parts: [{ text: SYSTEM_INSTRUCTION }] },
            generationConfig: {
              temperature: 0.6,
              maxOutputTokens: 4096,
            },
          })
        });

        if (response.ok) {
          const aiText = data.candidates?.[0]?.content?.parts
            ?.filter((part) => typeof part.text === "string")
            .map((part) => part.text)
            .join("\n")
            .trim();
          if (aiText) return res.json({ text: aiText });
        }
        providerFailures.push(`Gemini ${response.status}`);
        logProviderFailure("Gemini", `${response.status}: ${responseText}`);
      } catch (geminiError) {
        providerFailures.push("Gemini request error");
        logProviderFailure("Gemini", geminiError);
      }
    }

    // --- FALLBACK TO GROQ ---
    const groqKeys = (process.env.GROQ_API_KEYS || "").split(",").map(k => k.trim()).filter(Boolean);
    if (!imageBase64 && groqKeys.length > 0) {
      const groqUrl = "https://api.groq.com/openai/v1/chat/completions";
      const configuredGroqModel = process.env.GROQ_MODEL?.trim();
      const groqModel = !configuredGroqModel ||
        ["llama-3.2-11b-vision-preview", "llama-3.3-70b-versatile"].includes(configuredGroqModel)
        ? "openai/gpt-oss-120b"
        : configuredGroqModel;
      const messages = [
        { role: "system", content: SYSTEM_INSTRUCTION },
        ...history.map(msg => ({
          role: msg.isUser ? "user" : "assistant",
          content: msg.text
        })),
        { role: "user", content: userMessage }
      ];

      for (const key of groqKeys) {
        try {
          const { response, data, responseText } = await fetchJson(groqUrl, {
            method: "POST",
            headers: { "Content-Type": "application/json", "Authorization": `Bearer ${key}` },
            body: JSON.stringify({
              model: groqModel,
              messages,
              max_tokens: 4096,
              temperature: 0.6,
            })
          });

          if (response.ok) {
            const aiText = extractOpenAiText(data);
            if (aiText) return res.json({ text: aiText });
          }
          providerFailures.push(`Groq ${response.status}`);
          logProviderFailure("Groq", `${response.status}: ${responseText}`);
        } catch (e) {
          providerFailures.push("Groq request error");
          logProviderFailure("Groq", e);
          continue;
        }
      }
    }

    // --- FALLBACK TO MISTRAL (also supports image input) ---
    const mistralKeys = parseKeys(process.env.MISTRAL_API_KEYS);
    if (mistralKeys.length > 0) {
      const mistralModel = resolveModel(
        process.env.MISTRAL_MODEL,
        ["open-mistral-7b", "mistral-small-2501"],
        "mistral-small-latest",
      );
      const messages = buildOpenAiMessages(
        history,
        userMessage,
        imageBase64,
        imageMimeType,
      );

      for (const key of mistralKeys) {
        try {
          const { response, data, responseText } = await fetchJson(
            "https://api.mistral.ai/v1/chat/completions",
            {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${key}`,
              },
              body: JSON.stringify({
                model: mistralModel,
                messages,
                max_tokens: 4096,
                temperature: 0.6,
              }),
            },
          );

          if (response.ok) {
            const aiText = extractOpenAiText(data);
            if (aiText) return res.json({ text: aiText });
          }
          providerFailures.push(`Mistral ${response.status}`);
          logProviderFailure("Mistral", `${response.status}: ${responseText}`);
        } catch (error) {
          providerFailures.push("Mistral request error");
          logProviderFailure("Mistral", error);
        }
      }
    }

    // --- FINAL TEXT FALLBACK TO CLOUDFLARE WORKERS AI ---
    const cloudflareToken = process.env.CLOUDFLARE_TOKEN?.trim();
    const cloudflareAccountId = process.env.CLOUDFLARE_ACCOUNT_ID?.trim();
    if (!imageBase64 && cloudflareToken && cloudflareAccountId) {
      try {
        const cloudflareModel = resolveModel(
          process.env.CLOUDFLARE_MODEL,
          [
            "@cf/meta/llama-3.1-8b-instruct",
            "@cf/meta/infire-llama-3.1-8b-instruct",
          ],
          "@cf/openai/gpt-oss-120b",
        );
        const { response, data, responseText } = await fetchJson(
          `https://api.cloudflare.com/client/v4/accounts/${cloudflareAccountId}/ai/v1/chat/completions`,
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${cloudflareToken}`,
            },
            body: JSON.stringify({
              model: cloudflareModel,
              messages: buildOpenAiMessages(history, userMessage),
              max_tokens: 2048,
              temperature: 0.6,
            }),
          },
        );

        if (response.ok) {
          const aiText = extractOpenAiText(data) || data?.result?.response?.trim();
          if (aiText) return res.json({ text: aiText });
        }
        providerFailures.push(`Cloudflare ${response.status}`);
        logProviderFailure("Cloudflare", `${response.status}: ${responseText}`);
      } catch (error) {
        providerFailures.push("Cloudflare request error");
        logProviderFailure("Cloudflare", error);
      }
    }

    console.error("All AI providers failed:", providerFailures.join(" | "));
    res.status(503).json({ error: "AI service is temporarily unavailable. All providers failed." });
  } catch (error) {
    console.error("Critical Error:", error);
    res.status(500).json({ error: "Internal Server Error", details: error.message });
  }
});

// Vercel export
module.exports = app;

// Local listen
if (!process.env.VERCEL) {
  const PORT = process.env.PORT || 8080;
  app.listen(PORT, () => console.log(`Server running on ${PORT}`));
}
