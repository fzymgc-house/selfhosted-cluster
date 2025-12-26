// HCP Terraform to Discord webhook transformer

export default {
  async fetch(request, env) {
    // Only accept POST requests
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    try {
      const payload = await request.json();

      // Extract notification data
      const notification = payload.notifications?.[0];
      if (!notification) {
        return new Response("No notification data", { status: 400 });
      }

      // Color mapping for run status
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
      const color = colors[status] || 0x7289da;
      const emoji = statusEmoji[status] || "❓";

      // Build Discord embed
      const embed = {
        embeds: [
          {
            title: `${emoji} Terraform ${status.charAt(0).toUpperCase() + status.slice(1)}`,
            description: [
              `**Workspace:** ${payload.workspace_name || "unknown"}`,
              `**Run:** [${notification.run_id}](${notification.run_url})`,
              notification.run_message
                ? `**Message:** ${notification.run_message}`
                : null,
            ]
              .filter(Boolean)
              .join("\n"),
            color: color,
            timestamp: new Date().toISOString(),
            footer: {
              text: "HCP Terraform",
            },
          },
        ],
      };

      // Send to Discord
      const discordResponse = await fetch(env.DISCORD_WEBHOOK_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(embed),
      });

      if (!discordResponse.ok) {
        console.error("Discord error:", await discordResponse.text());
        return new Response("Discord webhook failed", { status: 502 });
      }

      return new Response("OK", { status: 200 });
    } catch (error) {
      console.error("Error processing webhook:", error);
      return new Response("Internal error", { status: 500 });
    }
  },
};
