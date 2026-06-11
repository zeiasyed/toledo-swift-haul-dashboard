/**
 * Deploy dashboard to Cloudflare Pages (Direct Upload API)
 */
import fs from "fs";
import path from "path";
import crypto from "crypto";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, "..");
const raw = fs.readFileSync(path.join(root, ".cloudflare-credentials.json"), "utf8").replace(/^\uFEFF/, "");
const creds = JSON.parse(raw);

const ACCOUNT_ID = "0f61b15e3b7ef041399aed19c79e6e7e";
const PROJECT = "toledo-swift-haul-app";
const DASHBOARD = path.join(root, "dashboard");

const headers = {
  "X-Auth-Email": creds.email,
  "X-Auth-Key": creds.globalKey,
};

function hashFile(filePath) {
  const data = fs.readFileSync(filePath);
  return crypto.createHash("sha256").update(data).digest("base64");
}

async function main() {
  const files = ["index.html", "styles.css", "app.js", "_redirects"];
  const manifest = {};
  const blobs = [];

  for (const name of files) {
    const filePath = path.join(DASHBOARD, name);
    if (!fs.existsSync(filePath)) throw new Error("Missing " + name);
    const hash = hashFile(filePath);
    manifest["/" + name] = hash;
    blobs.push({ hash, filePath, name });
  }

  const boundary = "----cfpages" + crypto.randomBytes(8).toString("hex");
  const parts = [];

  parts.push(
    `--${boundary}\r\n` +
      'Content-Disposition: form-data; name="manifest"\r\n' +
      "Content-Type: application/json\r\n\r\n" +
      JSON.stringify(manifest) +
      "\r\n"
  );

  for (const { hash, filePath, name } of blobs) {
    parts.push(
      `--${boundary}\r\n` +
        `Content-Disposition: form-data; name="${hash}"; filename="${name}"\r\n` +
        "Content-Type: application/octet-stream\r\n\r\n"
    );
    parts.push(fs.readFileSync(filePath));
    parts.push("\r\n");
  }
  parts.push(`--${boundary}--\r\n`);

  const body = Buffer.concat(parts.map((p) => (Buffer.isBuffer(p) ? p : Buffer.from(p, "utf8"))));

  const res = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/pages/projects/${PROJECT}/deployments`,
    {
      method: "POST",
      headers: {
        ...headers,
        "Content-Type": `multipart/form-data; boundary=${boundary}`,
      },
      body,
    }
  );

  const json = await res.json();
  if (!json.success) {
    console.error(JSON.stringify(json.errors));
    process.exit(1);
  }
  console.log("Deployed:", json.result.url);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
