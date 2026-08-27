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

// Simple health check
app.get("/health", (req, res) => {
  res.json({ ok: true, status: "Nyxra AI is Online" });
});

// Main Chat Route
app.post("/api/chat", async (req, res) => {
  try {
    const { conversationHistory, imageBase64 } = req.body;
    const userMessage = typeof req.body.userMessage === "string"
      ? req.body.userMessage.trim()
      : "";

    if (!userMessage && !imageBase64) {
      return res.status(400).json({ error: "A message or image is required." });
    }

    const history = normalizeHistory(conversationHistory, userMessage);
    
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
        const contents = history.slice(-10).map(msg => ({
          role: msg.isUser ? "user" : "model",
          parts: [{ text: msg.text }]
        }));
        const currentParts = [{ text: userMessage }];
        if (imageBase64) {
          currentParts.push({ inlineData: { mimeType: "image/jpeg", data: imageBase64 } });
        }
        contents.push({ role: "user", parts: currentParts });

        const response = await fetch(url, {
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
          const data = await response.json();
          const aiText = data.candidates?.[0]?.content?.parts?.[0]?.text;
          if (aiText) return res.json({ text: aiText });
        }
        const errorText = await response.text();
        console.error(`Gemini failed (${response.status}):`, errorText.slice(0, 500));
      } catch (geminiError) {
        console.error("Gemini failed, trying Groq...", geminiError.message);
      }
    }

    // --- FALLBACK TO GROQ ---
    const groqKeys = (process.env.GROQ_API_KEYS || "").split(",").map(k => k.trim()).filter(Boolean);
    if (groqKeys.length > 0) {
      const groqUrl = "https://api.groq.com/openai/v1/chat/completions";
      const configuredGroqModel = process.env.GROQ_MODEL?.trim();
      const groqModel = !configuredGroqModel ||
        ["llama-3.2-11b-vision-preview", "llama-3.3-70b-versatile"].includes(configuredGroqModel)
        ? "openai/gpt-oss-120b"
        : configuredGroqModel;
      const messages = [
        { role: "system", content: SYSTEM_INSTRUCTION },
        ...history.slice(-10).map(msg => ({
          role: msg.isUser ? "user" : "assistant",
          content: msg.text
        })),
        { role: "user", content: userMessage }
      ];

      for (const key of groqKeys) {
        try {
          const response = await fetch(groqUrl, {
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
            const data = await response.json();
            const aiText = data.choices?.[0]?.message?.content;
            if (aiText) return res.json({ text: aiText });
          }
          const errorText = await response.text();
          console.error(`Groq failed (${response.status}):`, errorText.slice(0, 500));
        } catch (e) {
          console.error("Groq request failed:", e.message);
          continue;
        }
      }
    }

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
