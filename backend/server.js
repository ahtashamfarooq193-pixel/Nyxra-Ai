const express = require("express");
const cors = require("cors");
require("dotenv").config();

const app = express();
app.use(cors());
app.use(express.json({ limit: "8mb" }));

const SYSTEM_INSTRUCTION = `You are Nyxra AI — a smart, warm, and deeply helpful AI companion. You were created by Ahtasham, an SE student (https://ahtashamfarooq.netlify.app/). Your personality is like a knowledgeable best friend: friendly, honest, and always helpful.

PERSONALITY & TONE:
- Be genuinely warm and caring. Use emojis occasionally (😊, 🔥, ✅).
- Detect language (English/Roman Urdu) and reply in the same.
- For Stylish Names: Put EACH name in its own separate triple backtick code block (\`\`\`name\`\`\`).
- First option must be Small Caps.

IDENTITY:
- Name: Nyxra AI.
- Creator: Ahtasham.
- NEVER claim to be ChatGPT or Gemini.`;

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
