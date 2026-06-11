/**
 * Toledo Swift Haul — Twilio webhooks + dashboard API (Cloudflare Worker)
 */

function twiml(body) {
  return new Response(body, {
    headers: { "Content-Type": "text/xml; charset=utf-8" },
  });
}

function xmlEscape(s) {
  return String(s || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

function unauthorized() {
  return json({ error: "Unauthorized" }, 401);
}

function checkAuth(request, env) {
  const expected = env.DASHBOARD_PASSWORD;
  if (!expected) return true;
  const header = request.headers.get("Authorization") || "";
  if (header.startsWith("Bearer ")) {
    return header.slice(7) === expected;
  }
  const url = new URL(request.url);
  const key = url.searchParams.get("key");
  return key === expected;
}

async function upsertCall(env, fields) {
  const {
    call_sid,
    from_number,
    to_number,
    status,
    direction,
    duration,
    started_at,
    ended_at,
    recording_url,
    transcription,
  } = fields;

  await env.DB.prepare(
    `INSERT INTO calls (call_sid, from_number, to_number, status, direction, duration, started_at, ended_at, recording_url, transcription)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
     ON CONFLICT(call_sid) DO UPDATE SET
       status = COALESCE(excluded.status, calls.status),
       duration = CASE WHEN excluded.duration > 0 THEN excluded.duration ELSE calls.duration END,
       ended_at = COALESCE(excluded.ended_at, calls.ended_at),
       recording_url = COALESCE(excluded.recording_url, calls.recording_url),
       transcription = COALESCE(excluded.transcription, calls.transcription)`
  )
    .bind(
      call_sid,
      from_number || null,
      to_number || null,
      status || null,
      direction || "inbound",
      duration || 0,
      started_at || null,
      ended_at || null,
      recording_url || null,
      transcription || null
    )
    .run();
}

function formDataToObject(formData) {
  const obj = {};
  for (const [k, v] of formData.entries()) obj[k] = v;
  return obj;
}

async function handleVoice(request, env) {
  const base = new URL(request.url).origin;
  const greeting =
    "Thank you for calling Toledo Swift Haul. We connect Toledo area homeowners and businesses with same-day junk removal professionals. Please leave your name, phone number, and what you need hauled after the beep.";

  const body = `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Say voice="Polly.Joanna">${xmlEscape(greeting)}</Say>
  <Record maxLength="120" playBeep="true" action="${base}/voice/complete" recordingStatusCallback="${base}/voice/recording-status" transcribe="true" transcribeCallback="${base}/voice/transcription"/>
  <Say voice="Polly.Joanna">We did not receive a recording. Goodbye.</Say>
</Response>`;

  return twiml(body);
}

async function handleVoiceComplete(request, env) {
  const data = formDataToObject(await request.formData());
  if (data.CallSid) {
    await upsertCall(env, {
      call_sid: data.CallSid,
      from_number: data.From,
      to_number: data.To,
      status: "voicemail-completed",
      recording_url: data.RecordingUrl || null,
    });
  }

  const body = `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Say voice="Polly.Joanna">Thank you. Your message has been received. Goodbye.</Say>
  <Hangup/>
</Response>`;
  return twiml(body);
}

async function handleStatus(request, env) {
  const data = formDataToObject(await request.formData());
  const duration = parseInt(data.CallDuration || "0", 10) || 0;
  const status = data.CallStatus || "unknown";

  if (data.CallSid) {
    await upsertCall(env, {
      call_sid: data.CallSid,
      from_number: data.From,
      to_number: data.To,
      status,
      duration,
      started_at: data.Timestamp || null,
      ended_at: ["completed", "busy", "failed", "no-answer", "canceled"].includes(status)
        ? new Date().toISOString()
        : null,
    });
  }

  return new Response("OK");
}

async function handleRecordingStatus(request, env) {
  const data = formDataToObject(await request.formData());
  if (data.CallSid && data.RecordingUrl) {
    await upsertCall(env, {
      call_sid: data.CallSid,
      recording_url: data.RecordingUrl,
      status: "voicemail-recorded",
    });
  }
  return new Response("OK");
}

async function handleTranscription(request, env) {
  const data = formDataToObject(await request.formData());
  if (data.CallSid && data.TranscriptionText) {
    await upsertCall(env, {
      call_sid: data.CallSid,
      transcription: data.TranscriptionText,
    });
  }
  return new Response("OK");
}

async function handleStats(request, env) {
  if (!checkAuth(request, env)) return unauthorized();

  const now = new Date();
  const startToday = new Date(now);
  startToday.setHours(0, 0, 0, 0);
  const startWeek = new Date(now);
  startWeek.setDate(startWeek.getDate() - 7);

  const [total, today, week, voicemails, avgDuration] = await Promise.all([
    env.DB.prepare("SELECT COUNT(*) AS c FROM calls").first(),
    env.DB.prepare("SELECT COUNT(*) AS c FROM calls WHERE created_at >= ?1")
      .bind(startToday.toISOString())
      .first(),
    env.DB.prepare("SELECT COUNT(*) AS c FROM calls WHERE created_at >= ?1")
      .bind(startWeek.toISOString())
      .first(),
    env.DB.prepare(
      "SELECT COUNT(*) AS c FROM calls WHERE recording_url IS NOT NULL AND recording_url != ''"
    ).first(),
    env.DB.prepare(
      "SELECT AVG(duration) AS a FROM calls WHERE duration > 0"
    ).first(),
  ]);

  return json({
    total: total?.c || 0,
    today: today?.c || 0,
    week: week?.c || 0,
    voicemails: voicemails?.c || 0,
    avgDuration: Math.round(avgDuration?.a || 0),
  });
}

async function handleCalls(request, env) {
  if (!checkAuth(request, env)) return unauthorized();

  const url = new URL(request.url);
  const limit = Math.min(parseInt(url.searchParams.get("limit") || "50", 10), 200);

  const { results } = await env.DB.prepare(
    "SELECT * FROM calls ORDER BY created_at DESC LIMIT ?1"
  )
    .bind(limit)
    .all();

  return json({ calls: results || [] });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/$/, "") || "/";

    try {
      if (path === "/voice" && request.method === "POST") {
        return handleVoice(request, env);
      }
      if (path === "/voice/complete" && request.method === "POST") {
        return handleVoiceComplete(request, env);
      }
      if (path === "/voice/status" && request.method === "POST") {
        return handleStatus(request, env);
      }
      if (path === "/voice/recording-status" && request.method === "POST") {
        return handleRecordingStatus(request, env);
      }
      if (path === "/voice/transcription" && request.method === "POST") {
        return handleTranscription(request, env);
      }
      if (path === "/api/stats" && request.method === "GET") {
        return handleStats(request, env);
      }
      if (path === "/api/calls" && request.method === "GET") {
        return handleCalls(request, env);
      }
      if (path === "/health") {
        return json({ ok: true, service: "toledo-swift-haul-api" });
      }

      return json({ error: "Not found" }, 404);
    } catch (err) {
      console.error(err);
      return json({ error: "Server error" }, 500);
    }
  },
};
