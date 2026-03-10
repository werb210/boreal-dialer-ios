/** @typedef {'online'|'busy'|'offline'} StaffStatus */

/** @typedef {{staffId:string,status:StaffStatus,source:'portal'|'dialer',lastSeen:number}} PresenceRecord */

const presenceMap = new Map();

function updatePresence(record) {
  presenceMap.set(record.staffId, record);
}

function getOnlineStaff() {
  const now = Date.now();
  return [...presenceMap.values()].filter((r) => r.status === 'online' && now - r.lastSeen < 30000);
}

function markBusy(staffId) {
  const rec = presenceMap.get(staffId);
  if (rec) rec.status = 'busy';
}

function markAvailable(staffId) {
  const rec = presenceMap.get(staffId);
  if (rec) rec.status = 'online';
}

module.exports = {
  updatePresence,
  getOnlineStaff,
  markBusy,
  markAvailable,
  presenceMap,
};
