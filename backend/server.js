const express = require("express");
const cors = require("cors");
const dns = require("node:dns/promises");
const net = require("node:net");
const {
  Document,
  HeadingLevel,
  Packer,
  Paragraph,
  TextRun,
} = require("docx");
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

function parseFeatureRequest(message) {
  const text = message.trim();
  const normalizeImagePrompt = (prompt) => prompt
    .replace(/\balion\b/gi, "a lion")
    .trim();
  const imageMatch = text.match(/^\s*\/(?:draw|image|imagine)\s+([\s\S]+)/i) ||
    text.match(/^\s*(?:draw|generate|create|make|banao|bana do|bna do)\s+(?:an?\s+)?(?:image|img|pic(?:ture)?|photo|tasveer)\s*(?:of|ki|ka|:)?\s*([\s\S]+)/i) ||
    text.match(/^\s*(?:mujhe\s+)?(?:ek\s+)?(?:image|img|pic(?:ture)?|photo|tasveer)\s+(?:banao|bana do|bna do|generate|create)\s*(?:of|ki|ka|:)?\s*([\s\S]+)/i) ||
    text.match(/^\s*(?:draw|generate|create|make|banao|bana do|bna do)\s+(?:an?\s+)?(.+?)\s+(?:image|img|pics?|picture|photo|tasveer)\s*[.!?]*$/i);
  if (imageMatch?.[1]?.trim()) {
    return { type: "image", prompt: normalizeImagePrompt(imageMatch[1]) };
  }

  const mentionsImage = /\b(?:image|img|pics?|picture|photo|tasveer)\b/i.test(text);
  const asksToCreate = /\b(?:draw|generate|create|make|bna|bnao|bana|banao)\b/i.test(text);
  if (mentionsImage && asksToCreate) {
    const romanUrduSubject = text.match(
      /\b(?:bna|bnao|bana|banao)\b\s*(?:k(?:ar)?\s*)?(?:do|du|de)?\s+(.+?)(?:\s+ki)?$/i,
    )?.[1]?.trim();
    return {
      type: "image",
      prompt: normalizeImagePrompt(romanUrduSubject || text),
    };
  }

  const urlMatch = text.match(/https?:\/\/[^\s<>()]+/i);
  const textWithoutUrl = urlMatch ? text.replace(urlMatch[0], "").replace(/[^a-z0-9]/gi, "") : "";
  if (urlMatch && (
    /^\s*\/audit\b/i.test(text) ||
    /\b(?:audit|analy[sz]e|check|review|inspect|dekho|dekh|website)\b/i.test(text) ||
    textWithoutUrl.length <= 20
  )) {
    return { type: "audit", url: urlMatch[0].replace(/[.,;!?]+$/, "") };
  }

  const docxCommand = text.match(/^\s*\/docx\s+([\s\S]+)/i);
  const wantsDocx = docxCommand ||
    (/\b(?:create|make|generate|prepare|banao|bana do|bna do)\b/i.test(text) &&
      /\b(?:docx|word document|word file)\b/i.test(text));
  if (wantsDocx) {
    const prompt = (docxCommand?.[1] || text)
      .replace(/\b(?:docx|word document|word file)\b/gi, "")
      .replace(/\s+/g, " ")
      .trim();
    return { type: "docx", prompt: prompt || "Create a useful general document." };
  }

  return { type: "chat" };
}

async function generateImage(prompt) {
  const apiKey = process.env.POLLINATIONS_API_KEY?.trim();
  if (!apiKey) throw new Error("Image generation is not configured.");

  const model = resolveModel(
    process.env.POLLINATIONS_IMAGE_MODEL,
    ["gemini", "openai"],
    "flux",
  );
  const width = Number.parseInt(process.env.POLLINATIONS_IMAGE_WIDTH, 10) || 1024;
  const height = Number.parseInt(process.env.POLLINATIONS_IMAGE_HEIGHT, 10) || 1024;
  const { response, data, responseText } = await fetchJson(
    "https://gen.pollinations.ai/v1/images/generations",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        prompt,
        model,
        n: 1,
        size: `${Math.min(Math.max(width, 256), 1536)}x${Math.min(Math.max(height, 256), 1536)}`,
        response_format: "url",
      }),
    },
  );

  const imageUrl = data?.data?.[0]?.url;
  if (!response.ok || typeof imageUrl !== "string") {
    throw new Error(`Pollinations ${response.status}: ${responseText}`);
  }
  return imageUrl;
}

function isPrivateAddress(address) {
  if (net.isIPv4(address)) {
    const [a, b] = address.split(".").map(Number);
    return a === 10 || a === 127 || a === 0 ||
      (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168) || a >= 224;
  }
  if (net.isIPv6(address)) {
    const value = address.toLowerCase();
    return value === "::1" || value === "::" || value.startsWith("fc") ||
      value.startsWith("fd") || value.startsWith("fe8") ||
      value.startsWith("fe9") || value.startsWith("fea") || value.startsWith("feb");
  }
  return true;
}

async function validatePublicUrl(value) {
  let url;
  try {
    url = new URL(value);
  } catch (_) {
    throw new Error("Please provide a valid website URL.");
  }
  if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) {
    throw new Error("Only public HTTP or HTTPS URLs are supported.");
  }
  if (["localhost", "localhost.localdomain"].includes(url.hostname.toLowerCase())) {
    throw new Error("Local or private websites cannot be audited.");
  }
  const addresses = await dns.lookup(url.hostname, { all: true });
  if (!addresses.length || addresses.some(({ address }) => isPrivateAddress(address))) {
    throw new Error("Local or private websites cannot be audited.");
  }
  return url;
}

async function fetchPublicHtml(initialUrl) {
  let currentUrl = await validatePublicUrl(initialUrl);
  for (let redirect = 0; redirect < 4; redirect += 1) {
    const startedAt = Date.now();
    const response = await fetch(currentUrl, {
      redirect: "manual",
      signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS),
      headers: {
        "User-Agent": "Nyxra-Audit/1.0 (+https://nyxra-ai-shamii.web.app)",
        Accept: "text/html,application/xhtml+xml",
      },
    });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.get("location");
      if (!location) throw new Error("Website returned an invalid redirect.");
      currentUrl = await validatePublicUrl(new URL(location, currentUrl).toString());
      continue;
    }
    const contentType = response.headers.get("content-type") || "";
    if (!contentType.includes("text/html") && !contentType.includes("application/xhtml+xml")) {
      throw new Error("The URL does not return an HTML webpage.");
    }
    const html = (await response.text()).slice(0, 2_000_000);
    return { response, html, url: currentUrl, elapsedMs: Date.now() - startedAt };
  }
  throw new Error("Website redirected too many times.");
}

function firstMatch(html, pattern) {
  return html.match(pattern)?.[1]?.replace(/\s+/g, " ").trim() || "";
}

function countMatches(html, pattern) {
  return (html.match(pattern) || []).length;
}

async function auditWebsite(urlValue) {
  const { response, html, url, elapsedMs } = await fetchPublicHtml(urlValue);
  const title = firstMatch(html, /<title[^>]*>([\s\S]*?)<\/title>/i);
  const description = firstMatch(html, /<meta[^>]+name=["']description["'][^>]+content=["']([^"']*)["'][^>]*>/i) ||
    firstMatch(html, /<meta[^>]+content=["']([^"']*)["'][^>]+name=["']description["'][^>]*>/i);
  const h1Count = countMatches(html, /<h1\b[^>]*>/gi);
  const imageCount = countMatches(html, /<img\b[^>]*>/gi);
  const missingAlt = (html.match(/<img\b[^>]*>/gi) || [])
    .filter((tag) => !/\balt\s*=\s*["'][^"']*["']/i.test(tag)).length;
  const linkCount = countMatches(html, /<a\b[^>]+href\s*=/gi);
  const hasViewport = /<meta[^>]+name=["']viewport["']/i.test(html);
  const hasCanonical = /<link[^>]+rel=["'][^"']*canonical[^"']*["']/i.test(html);
  const hasLang = /<html[^>]+lang=["'][^"']+["']/i.test(html);
  const hasRobotsNoIndex = /<meta[^>]+name=["']robots["'][^>]+content=["'][^"']*noindex/i.test(html);
  const securityHeaders = [
    "content-security-policy",
    "strict-transport-security",
    "x-content-type-options",
    "referrer-policy",
    "permissions-policy",
  ];
  const presentHeaders = securityHeaders.filter((name) => response.headers.has(name));
  const issues = [];
  if (!title) issues.push("Add a descriptive HTML title.");
  else if (title.length < 20 || title.length > 60) issues.push(`Adjust title length (${title.length}; aim for 20–60 characters).`);
  if (!description) issues.push("Add a meta description.");
  else if (description.length < 70 || description.length > 160) issues.push(`Adjust meta description length (${description.length}; aim for 70–160 characters).`);
  if (h1Count !== 1) issues.push(`Use one clear H1 heading (found ${h1Count}).`);
  if (!hasViewport) issues.push("Add a responsive viewport meta tag.");
  if (!hasCanonical) issues.push("Add a canonical URL.");
  if (!hasLang) issues.push("Declare the page language on the HTML element.");
  if (missingAlt) issues.push(`Add alt text to ${missingAlt} image(s).`);
  if (presentHeaders.length < securityHeaders.length) issues.push(`Add missing security headers (${securityHeaders.filter((h) => !presentHeaders.includes(h)).join(", ")}).`);

  const score = Math.max(0, 100 - issues.length * 8 - (hasRobotsNoIndex ? 12 : 0));
  const report = [
    `## Website Audit: ${url.hostname}`,
    "",
    `**Score:** ${score}/100  `,
    `**HTTP status:** ${response.status}  `,
    `**Initial response time:** ${elapsedMs} ms  `,
    `**Final URL:** ${url.toString()}`,
    "",
    "### SEO & Structure",
    `- Title: ${title ? `${title} (${title.length} characters)` : "Missing"}`,
    `- Meta description: ${description ? `${description.length} characters` : "Missing"}`,
    `- H1 headings: ${h1Count}`,
    `- Links found: ${linkCount}`,
    `- Images: ${imageCount}; missing alt: ${missingAlt}`,
    `- Canonical tag: ${hasCanonical ? "Present" : "Missing"}`,
    `- Mobile viewport: ${hasViewport ? "Present" : "Missing"}`,
    `- Language attribute: ${hasLang ? "Present" : "Missing"}`,
    `- Robots noindex: ${hasRobotsNoIndex ? "Yes" : "No"}`,
    "",
    "### Security Headers",
    ...securityHeaders.map((header) => `- ${header}: ${presentHeaders.includes(header) ? "Present" : "Missing"}`),
    "",
    "### Priority Recommendations",
    ...(issues.length ? issues.map((issue, index) => `${index + 1}. ${issue}`) : ["1. No major issues found in this lightweight audit."]),
    "",
    "_This is a server-side structural audit, not a full Lighthouse/browser performance test._",
  ].join("\n");
  return report;
}

function safeFileName(value) {
  const cleaned = value.replace(/[^a-z0-9 _-]/gi, "").trim().replace(/\s+/g, "-");
  return `${(cleaned || "nyxra-document").slice(0, 60)}.docx`;
}

function markdownToDocxParagraphs(markdown) {
  return markdown.split(/\r?\n/).filter((line) => line.trim()).map((line) => {
    const heading = line.match(/^(#{1,3})\s+(.+)/);
    if (heading) {
      const levels = [HeadingLevel.HEADING_1, HeadingLevel.HEADING_2, HeadingLevel.HEADING_3];
      return new Paragraph({ text: heading[2], heading: levels[heading[1].length - 1] });
    }
    const bullet = line.match(/^[-*]\s+(.+)/);
    if (bullet) return new Paragraph({ text: bullet[1], bullet: { level: 0 } });
    return new Paragraph({ children: [new TextRun(line.replace(/\*\*/g, ""))], spacing: { after: 160 } });
  });
}

async function createDocxResponse(res, content, prompt) {
  const title = prompt.split(/[.!?\n]/)[0].trim() || "Nyxra Document";
  const document = new Document({
    creator: "Nyxra AI",
    title,
    sections: [{
      children: [
        new Paragraph({ text: title, heading: HeadingLevel.TITLE }),
        ...markdownToDocxParagraphs(content),
      ],
    }],
  });
  const buffer = await Packer.toBuffer(document);
  return res.json({
    text: "Your Word document is ready. Use the download button below to save it.",
    generatedDocument: buffer.toString("base64"),
    documentName: safeFileName(title),
    documentMimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  });
}

async function sendTextResult(res, text, featureRequest) {
  if (featureRequest.type === "docx") {
    return createDocxResponse(res, text, featureRequest.prompt);
  }
  return res.json({ text });
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
    let userMessage = typeof payload.userMessage === "string"
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

    const featureRequest = parseFeatureRequest(userMessage);
    const history = normalizeHistory(conversationHistory, userMessage);
    const imageMimeType = detectImageMimeType(imageBase64);
    const providerFailures = [];

    if (featureRequest.type === "image") {
      try {
        const generatedImageUrl = await generateImage(featureRequest.prompt);
        return res.json({
          text: `Generated image for: ${featureRequest.prompt}`,
          generatedImageUrl,
        });
      } catch (error) {
        logProviderFailure("Image generation", error);
        return res.status(503).json({ error: "Image generation is temporarily unavailable." });
      }
    }

    if (featureRequest.type === "audit") {
      try {
        return res.json({ text: await auditWebsite(featureRequest.url) });
      } catch (error) {
        logProviderFailure("Website audit", error);
        return res.status(400).json({ error: error.message || "Website audit failed." });
      }
    }

    if (featureRequest.type === "docx") {
      userMessage = `Create a polished, accurate Word-document draft for this request: ${featureRequest.prompt}\n\n` +
        "Use a clear title, useful headings, concise paragraphs, and bullet points where helpful. " +
        "Return only the document content in Markdown; do not discuss the file creation process.";
    }
    
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
          if (aiText) return sendTextResult(res, aiText, featureRequest);
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
            if (aiText) return sendTextResult(res, aiText, featureRequest);
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
            if (aiText) return sendTextResult(res, aiText, featureRequest);
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
          if (aiText) return sendTextResult(res, aiText, featureRequest);
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
