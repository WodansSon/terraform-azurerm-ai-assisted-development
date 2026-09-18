const behaviorIds = ["WB-UX-SHUTDOWN-001"];

async function run() {
  return { requestRunnerShutdown: true };
}

module.exports = { name: "UI-triggered shutdown", behaviorIds, viewport: { width: 768, height: 900 }, run };
