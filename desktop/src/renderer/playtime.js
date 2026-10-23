// Play time: how long each game has been played, from the sessions RetroHub started and saw end.
// Loaded by the window (a <script>) and by the main process and tests (require). The Mac app's
// Playtime.swift has the same rules.
(function (exports) {
  /** Sessions shorter than this don't count: usually an emulator that couldn't start the game. */
  const MIN_SESSION_SECONDS = 10;

  /** The record with one more session added, or unchanged if the session was too short. */
  function addSession(playtime, id, seconds) {
    if (!(seconds >= MIN_SESSION_SECONDS)) return playtime;
    const old = playtime[id] || { seconds: 0, sessions: 0 };
    return { ...playtime, [id]: { seconds: old.seconds + Math.round(seconds), sessions: old.sessions + 1 } };
  }

  /** A renamed game's play time moves to its new path, added to any it already has. */
  function moveGame(playtime, from, to) {
    if (!playtime[from]) return playtime;
    const { [from]: moved, ...rest } = playtime;
    const old = rest[to] || { seconds: 0, sessions: 0 };
    return { ...rest, [to]: { seconds: old.seconds + moved.seconds, sessions: old.sessions + moved.sessions } };
  }

  function totalSeconds(playtime) {
    return Object.values(playtime).reduce((sum, p) => sum + p.seconds, 0);
  }

  /** "Under a minute", "12 min", "3 h 12 min", "40 h". */
  function format(seconds) {
    const minutes = Math.floor(seconds / 60);
    if (minutes < 1) return 'under a minute';
    if (minutes < 60) return `${minutes} min`;
    const hours = Math.floor(minutes / 60), rest = minutes % 60;
    return hours >= 10 || rest === 0 ? `${hours} h` : `${hours} h ${rest} min`;
  }

  Object.assign(exports, { MIN_SESSION_SECONDS, addSession, moveGame, totalSeconds, format });
})(typeof module !== 'undefined' ? module.exports : (window.PLAYTIME = {}));
