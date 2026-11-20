const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = ["WB-UX-ISOLATION-001"];

async function run({ page, baseUrl, assert }) {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await openWorkbench(page, baseUrl);
  assert(await page.evaluate(() => !matchMedia("(prefers-reduced-motion: reduce)").matches),
    "Storage isolation must be exercised with normal motion");
  const expected = await page.evaluate(async () => {
    const legacy = { ...structuredClone(state.session), id: crypto.randomUUID(), approverName: "Legacy fixture" };
    const database = await new Promise((resolve, reject) => {
      const request = indexedDB.open("hosted-rule-workbench-new", 1);
      request.onupgradeneeded = () => request.result.createObjectStore("sessions", { keyPath: "id" });
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    try {
      await new Promise((resolve, reject) => {
        const transaction = database.transaction("sessions", "readwrite");
        transaction.objectStore("sessions").put(legacy);
        transaction.oncomplete = resolve;
        transaction.onerror = () => reject(transaction.error);
      });
    } finally { database.close(); }
    localStorage.setItem("hosted-rule-workbench-new.active-session", legacy.id);
    state.session.approverName = "New fixture";
    await persistSession();
    return { currentId: state.session.id, legacyId: legacy.id };
  });
  await page.reload({ waitUntil: "domcontentloaded" });
  await page.waitForFunction(() => state.session && Number(document.querySelector("#catalog-count")?.textContent) > 0);
  const actual = await page.evaluate(async () => {
    const database = await new Promise((resolve, reject) => {
      const request = indexedDB.open("hosted-rule-workbench-new", 1);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    let legacy;
    try {
      legacy = await new Promise((resolve, reject) => {
        const request = database.transaction("sessions", "readonly").objectStore("sessions").getAll();
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
    } finally { database.close(); }
    return {
      id: state.session.id, name: state.session.approverName,
      legacy: legacy.map(session => ({ id: session.id, name: session.approverName })),
      legacyActive: localStorage.getItem("hosted-rule-workbench-new.active-session"),
      normalMotion: !matchMedia("(prefers-reduced-motion: reduce)").matches
    };
  });
  assert(actual.id === expected.currentId && actual.name === "New fixture",
    "New Workbench did not reopen its own persisted work independently of the legacy active key");
  assert(actual.legacy.length === 1 && actual.legacy[0].id === expected.legacyId
    && actual.legacy[0].name === "Legacy fixture" && actual.legacyActive === expected.legacyId,
  "Saving or reopening the New Workbench modified legacy storage");
  assert(actual.normalMotion, "Reload changed the required motion setting");
  return { behaviorIds };
}

module.exports = { behaviorIds, run };
