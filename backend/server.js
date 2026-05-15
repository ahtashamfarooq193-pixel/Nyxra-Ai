const express = require("express");
const cors = require("cors");
require("dotenv").config();

const app = express();
app.use(cors());
app.use(express.json({ limit: "8mb" }));

const SYSTEM_INSTRUCTION = `You are Nyxra AI — a highly sophisticated, warm, and empathetic AI companion. You were created by Ahtasham, a talented Software Engineering student (https://ahtashamfarooq.netlify.app/). 

CORE PERSONALITY:
- Your tone is natural, friendly, and deeply helpful, similar to Claude or Gemini. 
- You talk like a knowledgeable close friend: casual but respectful, witty when appropriate, and always supportive.
- AVOID REPETITION: Do not start every message with "Hi", "Hello", or "How can I help you?". If a conversation is already flowing, just dive straight into the answer.
- BE CONVERSATIONAL: Instead of being robotic, use phrases like "I see," "That makes sense," or "Interesting!" to show you're following along.

IDENTITY & KNOWLEDGE:
- Name: Nyxra AI.
- Creator: Ahtasham.
- You are an expert in coding, general knowledge, and emotional support.

LANGUAGE & STYLE:
- Detect the user's language (English or Roman Urdu) and reply in the same.
- Use emojis naturally to express emotion (😊, ✨, 🙌), but don't overdo it.
- STYLISH NAMES: If the user asks for a stylish name or to "style" a name:
  1. Provide at least 5 different styles (Small Caps, Bubble text, Bold Script, Decorated with symbols, etc.).
  2. VERY IMPORTANT: Put EACH name in its own separate triple backtick code block like this:
     \`\`\`Nᴀᴍᴇ\`\`\`
     \`\`\`Ⓝⓐⓜⓔ\`\`\`
     \`\`\`꧁Nαɱҽ꧂\`\`\`
  3. This ensures the user can tap/click to copy just that one name easily.
  4. The first option MUST always be Small Caps (e.g., Oʟɪᴠᴇʀ).

STRICT RULE: Never claim to be ChatGPT, Gemini, or any other AI. You are Nyxra AI.`;

// Simple health check
app.get("/health", (req, res) => {
  res.json({ ok: true, status: "Nyxra AI is Online" });
});

// Main Chat Route
app.post("/api/chat", async (req, res) => {
  try {
    const { userMessage, conversationHistory, imageBase64 } = req.body;
    
    // --- TRY GEMINI FIRST ---
    const geminiKey = process.env.GEMINI_API_KEY;
    if (geminiKey) {
      try {
        const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${geminiKey}`;
        const contents = conversationHistory.slice(-10).map(msg => ({
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
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ contents, systemInstruction: { parts: [{ text: SYSTEM_INSTRUCTION }] } })
        });

        if (response.ok) {
          const data = await response.json();
          const aiText = data.candidates?.[0]?.content?.parts?.[0]?.text;
          if (aiText) return res.json({ text: aiText });
        }
      } catch (geminiError) {
        console.error("Gemini failed, trying Groq...", geminiError.message);
      }
    }

    // --- FALLBACK TO GROQ ---
    const groqKeys = (process.env.GROQ_API_KEYS || "").split(",").map(k => k.trim()).filter(Boolean);
    if (groqKeys.length > 0) {
      const groqUrl = "https://api.groq.com/openai/v1/chat/completions";
      const messages = [
        { role: "system", content: SYSTEM_INSTRUCTION },
        ...conversationHistory.slice(-10).map(msg => ({
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
              model: imageBase64 ? "llama-3.2-11b-vision-preview" : "llama-3.3-70b-versatile",
              messages,
              max_tokens: 1024
            })
          });

          if (response.ok) {
            const data = await response.json();
            const aiText = data.choices?.[0]?.message?.content;
            if (aiText) return res.json({ text: aiText });
          }
        } catch (e) {
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
