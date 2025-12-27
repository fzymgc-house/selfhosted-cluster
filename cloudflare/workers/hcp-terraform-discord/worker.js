// HCP Terraform to Discord webhook transformer

/**
 * Verify HMAC-SHA512 signature from HCP Terraform.
 * @param {string} body - Raw request body
 * @param {string} signature - Signature from X-TFE-Notification-Signature header
 * @param {string} secret - HMAC secret token
 * @returns {Promise<boolean>} True if signature is valid
 */
async function verifyHmac(body, signature, secret) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"]
  );
  const mac = await crypto.subtle.sign("HMAC", key, encoder.encode(body));
  const computed = Array.from(new Uint8Array(mac))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return computed === signature;
}

export default {
  async fetch(request, env) {
    // Only accept POST requests
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    // Validate webhook URL is configured
    if (!env.DISCORD_WEBHOOK_URL) {
      console.error("DISCORD_WEBHOOK_URL secret is not configured");
      return new Response("Server misconfiguration", { status: 500 });
    }

    // Get raw body for HMAC verification (must be done before .json())
    const rawBody = await request.text();

    // Optional HMAC signature verification
    // If HMAC_SECRET is configured, require valid signature
    if (env.HMAC_SECRET) {
      const signature = request.headers.get("X-TFE-Notification-Signature");
      if (!signature) {
        console.error("Missing X-TFE-Notification-Signature header");
        return new Response("Missing signature", { status: 401 });
      }
      const valid = await verifyHmac(rawBody, signature, env.HMAC_SECRET);
      if (!valid) {
        console.error("Invalid HMAC signature");
        return new Response("Invalid signature", { status: 401 });
      }
    }

    // Parse request body
    let payload;
    try {
      payload = JSON.parse(rawBody);
    } catch (parseError) {
      console.error("Failed to parse request body:", parseError.message);
      return new Response("Invalid JSON payload", { status: 400 });
    }

    // Extract notification data
    const notification = payload.notifications?.[0];
    if (!notification) {
      console.error("Missing notifications in payload:", {
        workspace: payload.workspace_name,
        keys: Object.keys(payload),
      });
      return new Response("No notification data", { status: 400 });
    }

    // Color mapping for run status
    // See: https://developer.hashicorp.com/terraform/cloud-docs/api-docs/notification-configurations
    const colors = {
      planned: 0x3498db, // blue
      applied: 0x2ecc71, // green
      errored: 0xe74c3c, // red
      canceled: 0x95a5a6, // gray
      planning: 0xf39c12, // orange
      applying: 0xf39c12, // orange
      discarded: 0x95a5a6, // gray
    };

    const statusEmoji = {
      planned: "📋",
      applied: "✅",
      errored: "❌",
      canceled: "🚫",
      planning: "🔄",
      applying: "🔄",
      discarded: "🗑️",
    };

    const status = notification.run_status || "unknown";
    const color = colors[status];
    const emoji = statusEmoji[status];

    // Log unknown statuses for future updates
    if (!color || !emoji) {
      console.warn("Unknown run status encountered:", {
        status,
        runId: notification.run_id,
        workspace: payload.workspace_name,
      });
    }

    // Build Discord embed
    const embed = {
      embeds: [
        {
          title: `${emoji || "❓"} Terraform ${status.charAt(0).toUpperCase() + status.slice(1)}`,
          description: [
            `**Workspace:** ${payload.workspace_name || "unknown"}`,
            `**Run:** [${notification.run_id}](${notification.run_url})`,
            notification.run_message
              ? `**Message:** ${notification.run_message}`
              : null,
          ]
            .filter(Boolean)
            .join("\n"),
          color: color || 0x7289da,
          timestamp: new Date().toISOString(),
          footer: {
            text: "HCP Terraform",
          },
        },
      ],
    };

    // Send to Discord
    let discordResponse;
    try {
      discordResponse = await fetch(env.DISCORD_WEBHOOK_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(embed),
      });
    } catch (networkError) {
      console.error("Network error reaching Discord:", {
        error: networkError.message,
        workspace: payload.workspace_name,
        runId: notification.run_id,
      });
      return new Response("Failed to reach Discord", { status: 503 });
    }

    if (!discordResponse.ok) {
      const errorBody = await discordResponse.text();
      console.error("Discord API error:", {
        status: discordResponse.status,
        error: errorBody,
        workspace: payload.workspace_name,
        runId: notification.run_id,
      });

      if (discordResponse.status === 429) {
        // Pass through Discord's Retry-After header so HCP TF can retry appropriately
        const retryAfter = discordResponse.headers.get("Retry-After") || "60";
        return new Response("Discord rate limited", {
          status: 503,
          headers: { "Retry-After": retryAfter },
        });
      }
      return new Response(`Discord webhook failed: ${discordResponse.status}`, {
        status: 502,
      });
    }

    return new Response("OK", { status: 200 });
  },
};
