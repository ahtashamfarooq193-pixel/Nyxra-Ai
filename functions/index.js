const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");

admin.initializeApp();

const groqKeysSecret = defineSecret("GROQ_API_KEYS");
const groqBaseUrlSecret = defineSecret("GROQ_BASE_URL");
const groqModelSecret = defineSecret("GROQ_MODEL");
const mistralKeysSecret = defineSecret("MISTRAL_API_KEYS");
const mistralModelSecret = defineSecret("MISTRAL_MODEL");
const cloudflareTokenSecret = defineSecret("CLOUDFLARE_TOKEN");
const cloudflareAccountSecret = defineSecret("CLOUDFLARE_ACCOUNT_ID");

const SYSTEM_INSTRUCTION =
  `You are Nyxra AI — a highly sophisticated, warm, and empathetic AI companion. You were created by Ahtasham, a talented Software Engineering student (https://ahtashamfarooq.netlify.app/). 

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
- For Stylish Names: Put EACH name in its own separate triple backtick code block (\`\`\`name\`\`\`). The first option should be in Small Caps.

STRICT RULE: Never claim to be ChatGPT, Gemini, or any other AI. You are Nyxra AI.`;

function parseCsvSecret(secretValue) {
  return (secretValue || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
}

function buildMessages(userMessage, conversationHistory, imageBase64) {
  const messages = [{ role: "system", content: SYSTEM_INSTRUCTION }];
  const relevantHistory = Array.isArray(conversationHistory)
    ? conversationHistory.slice(-10)
    : [];

  for (const entry of relevantHistory) {
    if (!entry || typeof entry.text !== "string") continue;
    messages.push({
      role: entry.isUser ? "user" : "assistant",
      content: entry.text,
    });
  }

  if (imageBase64) {
    messages.push({
      role: "user",
      content: [
        {
          type: "text",
          text: userMessage || "Analyze this image.",
        },
        {
          type: "image_url",
          image_url: {
            url: `data:image/jpeg;base64,${imageBase64}`,
          },
        },
      ],
    });
  } else {
    messages.push({ role: "user", content: userMessage });
  }

  return messages;
}

async function callGroq({ messages, imageBase64 }) {
  const apiKeys = parseCsvSecret(groqKeysSecret.value());
  const baseUrl = (groqBaseUrlSecret.value() || "https://api.groq.com/openai/v1").trim();
  const model = (groqModelSecret.value() || "llama-3.3-70b-versatile").trim();
  const requestModel = imageBase64 ? "llama-3.2-11b-vision-preview" : model;

  for (const apiKey of apiKeys) {
    const response = await fetch(`${baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
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
      continue;
    }

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Groq error ${response.status}: ${errorText}`);
    }

    const data = await response.json();
    return data.choices?.[0]?.message?.content?.trim() || "";
  }

  throw new Error("No Groq API keys succeeded.");
}

async function callMistral({ messages }) {
  const apiKeys = parseCsvSecret(mistralKeysSecret.value());
  const model = (mistralModelSecret.value() || "open-mistral-7b").trim();

  for (const apiKey of apiKeys) {
    const response = await fetch("https://api.mistral.ai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        messages,
        stream: false,
      }),
    });

    if (response.status === 429) {
      continue;
    }

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Mistral error ${response.status}: ${errorText}`);
    }

    const data = await response.json();
    return data.choices?.[0]?.message?.content?.trim() || "";
  }

  throw new Error("No Mistral API keys succeeded.");
}

async function callCloudflare({ messages }) {
  const token = (cloudflareTokenSecret.value() || "").trim();
  const accountId = (cloudflareAccountSecret.value() || "").trim();

  if (!token || !accountId) {
    throw new Error("Cloudflare fallback is not configured.");
  }

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
    },
  );

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Cloudflare error ${response.status}: ${errorText}`);
  }

  const data = await response.json();
  return data.result?.response?.trim() || data.choices?.[0]?.message?.content?.trim() || "";
}

async function generateWithFallback(messages, imageBase64) {
  const providers = [
    { name: "Groq", call: () => callGroq({ messages, imageBase64 }) },
    { name: "Mistral", call: () => callMistral({ messages }) },
    { name: "Cloudflare", call: () => callCloudflare({ messages }) },
  ];

  const failures = [];

  for (const provider of providers) {
    try {
      const text = await provider.call();
      if (text) {
        return text;
      }
      failures.push(`${provider.name}: empty response`);
    } catch (error) {
      failures.push(`${provider.name}: ${error.message}`);
    }
  }

  throw new Error(failures.join(" | "));
}

exports.generateAiResponse = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 60,
    memory: "512MiB",
    secrets: [
      groqKeysSecret,
      groqBaseUrlSecret,
      groqModelSecret,
      mistralKeysSecret,
      mistralModelSecret,
      cloudflareTokenSecret,
      cloudflareAccountSecret,
    ],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Please sign in to use Nyxra AI.");
    }

    const userMessage = typeof request.data?.userMessage === "string"
      ? request.data.userMessage.trim()
      : "";
    const conversationHistory = request.data?.conversationHistory || [];
    const imageBase64 = typeof request.data?.imageBase64 === "string"
      ? request.data.imageBase64.trim()
      : "";

    if (!userMessage && !imageBase64) {
      throw new HttpsError("invalid-argument", "Message or image is required.");
    }

    const messages = buildMessages(userMessage, conversationHistory, imageBase64);

    try {
      const text = await generateWithFallback(messages, imageBase64);
      if (!text) {
        throw new Error("Empty AI response.");
      }

      return { text };
    } catch (error) {
      console.error("generateAiResponse failed", error);
      throw new HttpsError("internal", "AI service is temporarily unavailable.");
    }
  },
);
