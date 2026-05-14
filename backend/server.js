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
    const apiKey = process.env.GEMINI_API_KEY;

    if (!apiKey) {
      return res.status(500).json({ error: "Gemini API Key missing on server." });
    }

    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`;
    
    // Prepare contents
    const contents = conversationHistory.slice(-10).map(msg => ({
      role: msg.isUser ? "user" : "model",
      parts: [{ text: msg.text }]
    }));

    // Add current message
    const currentParts = [{ text: userMessage }];
    if (imageBase64) {
      currentParts.push({
        inlineData: {
          mimeType: "image/jpeg",
          data: imageBase64
        }
      });
    }
    contents.push({ role: "user", parts: currentParts });

    const payload = {
      contents,
      systemInstruction: { parts: [{ text: SYSTEM_INSTRUCTION }] }
    };

    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });

    const data = await response.json();
    const aiText = data.candidates?.[0]?.content?.parts?.[0]?.text || "I'm sorry, I couldn't process that.";

    res.json({ text: aiText });
  } catch (error) {
    console.error("Error:", error);
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
