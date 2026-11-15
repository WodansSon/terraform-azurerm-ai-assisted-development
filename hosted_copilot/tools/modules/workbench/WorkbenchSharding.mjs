import { requireSourceObject } from './WorkbenchSourceRecords.mjs';

export const defaultWorkbenchBudgets = Object.freeze({ stagePayloadBudgetBytes: 262144, evaluatorPayloadBudgetBytes: 393216 });
export const synthesisAssessmentLimit = 16;

// Keep assessment and rule identities disjoint when validating mixed component partitions.
export function reconciliationMemberKeys(component) {
  if (!Array.isArray(component.assessmentResultIds) || !Array.isArray(component.ruleVersionIds) ||
    [...component.assessmentResultIds, ...component.ruleVersionIds].some(id => !Number.isSafeInteger(id) || id < 1)) {
    throw new Error('Reconciliation membership requires typed assessment and rule arrays');
  }
  return [...component.assessmentResultIds.map(id => `assessment:${id}`), ...component.ruleVersionIds.map(id => `rule:${id}`)];
}

// Validate separate stage-data and complete-envelope limits without allowing the inner budget to exceed the outer one.
export function readWorkbenchBudgets(value = defaultWorkbenchBudgets) {
  const fields = ['stagePayloadBudgetBytes', 'evaluatorPayloadBudgetBytes'];
  requireSourceObject(value, fields, fields, 'Native execution budgets');
  if (fields.some(field => !Number.isSafeInteger(value[field]) || value[field] < 1) || value.stagePayloadBudgetBytes > value.evaluatorPayloadBudgetBytes) {
    throw new Error('Native execution requires positive byte budgets with stage input within the complete evaluator budget');
  }
  return { ...value };
}

// Preserve safe structured sizing details so callers can distinguish an oversized request from evaluator failure.
export function payloadBudgetError(phase, payloadBytes, limitBytes) {
  const error = new Error(`Native ${phase} input requires ${payloadBytes} bytes and exceeds its ${limitBytes}-byte evaluator budget`);
  error.code = 'workbench-evaluator-input-budget-exceeded';
  error.phase = phase;
  error.payloadBytes = payloadBytes;
  error.limitBytes = limitBytes;
  return error;
}

// Cover every within-block and cross-block component comparison while keeping each measured request inside both budgets.
export function planConsolidationShards(components, budgetValue, measureEnvelope) {
  const budgets = readWorkbenchBudgets(budgetValue);
  if (!Array.isArray(components) || typeof measureEnvelope !== 'function') throw new Error('Consolidation sharding requires components and complete envelope measurement');
  const ids = new Set();
  const assessments = new Set();
  for (const component of components) {
    const fields = ['componentId', 'semanticSummary', 'assessmentResultIds', 'ruleVersionIds'];
    requireSourceObject(component, fields, fields, 'Consolidation component');
    if (!Number.isSafeInteger(component.componentId) || component.componentId < 1 || ids.has(component.componentId) ||
      typeof component.semanticSummary !== 'string' || !component.semanticSummary.trim() ||
      reconciliationMemberKeys(component).length === 0) {
      throw new Error('Consolidation requires distinct components with complete semantic summaries and membership');
    }
    ids.add(component.componentId);
    for (const id of reconciliationMemberKeys(component)) {
      if (assessments.has(id)) throw new Error('Consolidation component membership must be an exact nonoverlapping partition');
      assessments.add(id);
    }
  }
  const ordered = [...components].sort((left, right) => left.componentId - right.componentId);
  const bytes = values => Buffer.byteLength(JSON.stringify({ components: values }), 'utf8');
  const blockBudget = Math.max(bytes([]) + 1, Math.floor((budgets.stagePayloadBudgetBytes + bytes([])) / 2));
  const blocks = [];
  let current = [];
  for (const component of ordered) {
    if (current.length && bytes([...current, component]) > blockBudget) { blocks.push(current); current = []; }
    if (bytes([component]) > budgets.stagePayloadBudgetBytes) throw payloadBudgetError('consolidation', bytes([component]), budgets.stagePayloadBudgetBytes);
    current.push(component);
  }
  if (current.length) blocks.push(current);
  while (true) {
    const shards = [];
    let splitIndex = null;
    for (let left = 0; left < blocks.length && splitIndex === null; left++) {
      for (let right = left; right < blocks.length; right++) {
        const members = left === right ? blocks[left] : [...blocks[left], ...blocks[right]];
        const measurement = measureEnvelope(members);
        if (!measurement || !Number.isSafeInteger(measurement.inputBytes) || measurement.inputBytes < 1 ||
          !Number.isSafeInteger(measurement.payloadBytes) || measurement.payloadBytes < measurement.inputBytes) {
          throw new Error('Consolidation measurement requires the complete data and evaluator envelope byte counts');
        }
        const { inputBytes, payloadBytes } = measurement;
        if (inputBytes > budgets.stagePayloadBudgetBytes || payloadBytes > budgets.evaluatorPayloadBudgetBytes) {
          const largest = blocks[left].length >= blocks[right].length ? left : right;
          if (blocks[largest].length === 1) throw inputBytes > budgets.stagePayloadBudgetBytes
            ? payloadBudgetError('consolidation', inputBytes, budgets.stagePayloadBudgetBytes)
            : payloadBudgetError('consolidation', payloadBytes, budgets.evaluatorPayloadBudgetBytes);
          splitIndex = largest;
          break;
        }
        shards.push({ componentIds: members.map(component => component.componentId), inputBytes, payloadBytes });
      }
    }
    if (splitIndex === null) return shards;
    const block = blocks[splitIndex];
    const midpoint = Math.ceil(block.length / 2);
    blocks.splice(splitIndex, 1, block.slice(0, midpoint), block.slice(midpoint));
  }
}

// Pack independent whole relationship components; refuse an oversized component rather than splitting its decision context.
export function planAdjudicationShards(components, budgetValue, measureEnvelope) {
  const budgets = readWorkbenchBudgets(budgetValue);
  if (!Array.isArray(components) || new Set(components.map(component => component.componentId)).size !== components.length ||
    components.some(component => !Number.isSafeInteger(component.componentId) || component.componentId < 1)) {
    throw new Error('Adjudication planning requires unique positive component identities');
  }
  if (typeof measureEnvelope !== 'function') throw new Error('Adjudication planning requires complete envelope measurement');
  const measure = componentIds => {
    const measurement = measureEnvelope({ componentIds });
    if (!measurement || !Number.isSafeInteger(measurement.inputBytes) || measurement.inputBytes < 1 ||
      !Number.isSafeInteger(measurement.payloadBytes) || measurement.payloadBytes < measurement.inputBytes) {
      throw new Error('Adjudication measurement requires complete input and evaluator envelope byte counts');
    }
    return { componentIds, ...measurement };
  };
  const fits = job => job.inputBytes <= budgets.stagePayloadBudgetBytes && job.payloadBytes <= budgets.evaluatorPayloadBudgetBytes;
  const jobs = [];
  let pending;
  for (const component of components.toSorted((left, right) => left.componentId - right.componentId)) {
    const whole = measure([component.componentId]);
    if (!fits(whole)) throw whole.inputBytes > budgets.stagePayloadBudgetBytes
      ? payloadBudgetError('adjudication', whole.inputBytes, budgets.stagePayloadBudgetBytes)
      : payloadBudgetError('adjudication', whole.payloadBytes, budgets.evaluatorPayloadBudgetBytes);
    const combined = pending ? measure([...pending.componentIds, component.componentId]) : whole;
    if (pending && !fits(combined)) { jobs.push(pending); pending = whole; }
    else pending = combined;
  }
  if (pending) jobs.push(pending);
  return jobs;
}

// Union connected shard outcomes only after verifying full comparison coverage and preservation of original components.
export function mergeConsolidationShards(components, shards, results) {
  if (!Array.isArray(shards) || !Array.isArray(results) || results.length !== shards.length) throw new Error('Consolidation merge requires every planned shard result');
  const owners = new Map();
  const parents = new Map();
  const byId = new Map();
  for (const component of components) {
    if (byId.has(component.componentId)) throw new Error('Consolidation merge refuses repeated input components');
    byId.set(component.componentId, component);
    parents.set(component.componentId, component.componentId);
    for (const id of reconciliationMemberKeys(component)) {
      if (owners.has(id)) throw new Error('Consolidation merge refuses overlapping original membership');
      owners.set(id, component.componentId);
    }
  }
  // Follow union links to the surviving representative shared by transitively merged components.
  const root = id => {
    let current = id;
    while (parents.get(current) !== current) current = parents.get(current);
    return current;
  };
  const pairs = new Set();
  for (const [index, shard] of shards.entries()) {
    const result = results[index];
    if (JSON.stringify(result.componentIds) !== JSON.stringify(shard.componentIds) || new Set(shard.componentIds).size !== shard.componentIds.length ||
      shard.componentIds.some(id => !byId.has(id))) throw new Error('Consolidation merge refuses foreign or repeated shard inputs');
    const expected = new Set(shard.componentIds.flatMap(id => reconciliationMemberKeys(byId.get(id))));
    const assigned = new Map();
    for (const [groupIndex, group] of result.components.entries()) {
      const memberKeys = reconciliationMemberKeys(group);
      if (!memberKeys.length) throw new Error('Consolidation merge refuses empty groups');
      for (const id of memberKeys) {
        if (!expected.has(id) || assigned.has(id)) throw new Error('Consolidation merge refuses foreign or repeated shard membership');
        assigned.set(id, groupIndex);
      }
      const ids = [...new Set(memberKeys.map(id => owners.get(id)))];
      for (const id of ids.slice(1)) parents.set(root(id), root(ids[0]));
    }
    if (assigned.size !== expected.size) throw new Error('Consolidation merge requires exact complete shard membership');
    for (const id of shard.componentIds) {
      const members = reconciliationMemberKeys(byId.get(id));
      if (members.some(member => assigned.get(member) !== assigned.get(members[0]))) throw new Error('Consolidation cannot split an original component');
      for (const other of shard.componentIds) pairs.add(`${Math.min(id, other)}:${Math.max(id, other)}`);
    }
  }
  for (const id of byId.keys()) for (const other of byId.keys()) {
    if (!pairs.has(`${Math.min(id, other)}:${Math.max(id, other)}`)) throw new Error('Consolidation merge requires complete within-block and cross-block comparison coverage');
  }
  const groups = new Map();
  for (const id of [...byId.keys()].sort((left, right) => left - right)) {
    const key = root(id);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(byId.get(id));
  }
  return [...groups.values()].map(members => ({ componentIds: members.map(member => member.componentId),
    assessmentResultIds: members.flatMap(member => member.assessmentResultIds).sort((left, right) => left - right),
    ruleVersionIds: members.flatMap(member => member.ruleVersionIds).sort((left, right) => left - right),
    semanticSummary: members.map(member => member.semanticSummary).join('\n') }));
}
