// HCP Terraform to Discord webhook transformer

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

    // Parse request body
    let payload;
    try {
      payload = await request.json();
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
        return new Response("Discord rate limited", { status: 503 });
      }
      return new Response(`Discord webhook failed: ${discordResponse.status}`, {
        status: 502,
      });
    }

    return new Response("OK", { status: 200 });
  },
};
