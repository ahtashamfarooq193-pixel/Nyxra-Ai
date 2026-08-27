# Nyxra Backend

## Local run

1. Copy `.env.example` to `.env`
2. Add your real API keys in `.env`
3. Install and start:

```bash
npm install
npm run dev
```

Server runs on `http://localhost:8080`.

## API

- `GET /health`
- `POST /api/chat`

Request body:

```json
{
  "userMessage": "Hello",
  "conversationHistory": [
    { "text": "Hi", "isUser": false }
  ],
  "imageBase64": null
}
```

## AI provider fallback

The chat route tries configured providers in this order:

1. Gemini (text and images)
2. Groq (text)
3. Mistral (text and images)
4. Cloudflare Workers AI (text)

Provider calls have timeouts, invalid retired model values are migrated to
supported defaults, and the next configured provider is tried automatically.
At least one provider API key must be configured in the deployment environment.

Response body:

```json
{
  "text": "Assistant response..."
}
```

## Flutter connection

Run Flutter with backend URL:

```bash
flutter run --dart-define=BACKEND_BASE_URL=http://localhost:8080
```

For Android emulator, use:

```bash
flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:8080
```

## Deploy (Railway)

1. Push repo to GitHub
2. Create new Railway project from the repo
3. Set root directory to `backend`
4. Add environment variables from `.env` into Railway Variables
5. Deploy and copy generated backend URL
6. Run app with:

```bash
flutter run --dart-define=BACKEND_BASE_URL=https://your-railway-url.up.railway.app
```

## Deploy (Vercel)

1. Import the same repo in Vercel
2. Set project root directory to `backend`
3. Add environment variables from `.env`
4. Deploy and use generated URL:

```bash
flutter run --dart-define=BACKEND_BASE_URL=https://your-project.vercel.app
```
