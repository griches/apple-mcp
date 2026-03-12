import { execFile } from "node:child_process";

export function sanitize(input: string): string {
  return input
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\r\n/g, "\\n")
    .replace(/\r/g, "\\n")
    .replace(/\n/g, "\\n");
}

export function runAppleScript(script: string, timeout = 30000): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile("osascript", ["-e", script], { maxBuffer: 10 * 1024 * 1024, timeout }, (error, stdout, stderr) => {
      if (error) {
        if ((error as NodeJS.ErrnoException & { killed?: boolean }).killed) {
          reject(new Error("AppleScript timed out"));
          return;
        }
        reject(new Error(`AppleScript error: ${stderr || error.message}`));
        return;
      }
      resolve(stdout.trimEnd());
    });
  });
}

export interface NowPlayingInfo {
  state: "playing" | "paused" | "stopped";
  track?: {
    name: string;
    artist: string;
    album: string;
    duration: number;
    position: number;
    loved: boolean;
    rating: number;
  };
  volume: number;
  shuffle: boolean;
  repeat: "off" | "one" | "all";
}

export async function getNowPlaying(): Promise<NowPlayingInfo> {
  const script = `
tell application "Music"
  set st to player state as text
  set vol to sound volume
  set sh to shuffle enabled as text
  set rep to song repeat as text
  if player state is not stopped then
    set t to current track
    set tName to name of t
    set tArtist to artist of t
    set tAlbum to album of t
    set tDuration to duration of t
    set tPosition to player position
    set tLoved to false
    try
      set tLoved to loved of t
    end try
    set tRating to 0
    try
      set tRating to rating of t
    end try
    return st & "|||" & vol & "|||" & sh & "|||" & rep & "|||" & tName & "|||" & tArtist & "|||" & tAlbum & "|||" & tDuration & "|||" & tPosition & "|||" & (tLoved as text) & "|||" & tRating
  else
    return st & "|||" & vol & "|||" & sh & "|||" & rep
  end if
end tell`;
  const raw = await runAppleScript(script);
  const parts = raw.split("|||");
  const stateRaw = parts[0]?.trim() ?? "stopped";
  const state = stateRaw === "playing" ? "playing" : stateRaw === "paused" ? "paused" : "stopped";
  const volume = parseInt(parts[1]?.trim() ?? "0", 10);
  const shuffle = parts[2]?.trim() === "true";
  const repeatRaw = parts[3]?.trim() ?? "off";
  const repeat: "off" | "one" | "all" = repeatRaw === "one" ? "one" : repeatRaw === "all" ? "all" : "off";

  if (state === "stopped" || parts.length < 8) {
    return { state, volume, shuffle, repeat };
  }

  return {
    state,
    volume,
    shuffle,
    repeat,
    track: {
      name: parts[4]?.trim() ?? "",
      artist: parts[5]?.trim() ?? "",
      album: parts[6]?.trim() ?? "",
      duration: parseFloat(parts[7]?.trim() ?? "0"),
      position: parseFloat(parts[8]?.trim() ?? "0"),
      loved: parts[9]?.trim() === "true",
      rating: parseInt(parts[10]?.trim() ?? "0", 10),
    },
  };
}

export async function play(): Promise<string> {
  await runAppleScript(`tell application "Music" to play`);
  return "Playback started";
}

export async function pause(): Promise<string> {
  await runAppleScript(`tell application "Music" to pause`);
  return "Playback paused";
}

export async function nextTrack(): Promise<string> {
  await runAppleScript(`tell application "Music" to next track`);
  return "Skipped to next track";
}

export async function previousTrack(): Promise<string> {
  await runAppleScript(`tell application "Music" to back track`);
  return "Went to previous track";
}

export async function setVolume(volume: number): Promise<string> {
  const v = Math.max(0, Math.min(100, Math.round(volume)));
  await runAppleScript(`tell application "Music" to set sound volume to ${v}`);
  return `Volume set to ${v}`;
}

export async function setShuffle(enabled: boolean): Promise<string> {
  await runAppleScript(`tell application "Music" to set shuffle enabled to ${enabled}`);
  return `Shuffle ${enabled ? "enabled" : "disabled"}`;
}

export async function setRepeat(mode: "off" | "one" | "all"): Promise<string> {
  const modeMap = { off: "off", one: "one", all: "all" };
  await runAppleScript(`tell application "Music" to set song repeat to ${modeMap[mode]}`);
  return `Repeat set to ${mode}`;
}

export async function seek(seconds: number): Promise<string> {
  const pos = Math.max(0, seconds);
  await runAppleScript(`tell application "Music" to set player position to ${pos}`);
  return `Seeked to ${pos}s`;
}

export interface Track {
  id: string;
  name: string;
  artist: string;
  album: string;
  duration: number;
}

export async function search(query: string, limit = 25): Promise<Track[]> {
  const safeQuery = sanitize(query);
  const script = `
tell application "Music"
  set results to search playlist "Library" for "${safeQuery}"
  set lim to ${limit}
  if (count of results) < lim then set lim to count of results
  set output to {}
  repeat with i from 1 to lim
    set t to item i of results
    set end of output to (id of t as text) & "|||" & (name of t) & "|||" & (artist of t) & "|||" & (album of t) & "|||" & (duration of t as text)
  end repeat
  set AppleScript's text item delimiters to "<<<>>>"
  return output as text
end tell`;
  const raw = await runAppleScript(script);
  if (!raw) return [];
  return raw.split("<<<>>>").map((record) => {
    const parts = record.split("|||");
    return {
      id: parts[0]?.trim() ?? "",
      name: parts[1]?.trim() ?? "",
      artist: parts[2]?.trim() ?? "",
      album: parts[3]?.trim() ?? "",
      duration: parseFloat(parts[4]?.trim() ?? "0"),
    };
  });
}

export async function playTrack(name: string, artist?: string): Promise<string> {
  const safeQuery = sanitize(artist ? `${name} ${artist}` : name);
  const safeName = sanitize(name);
  const script = `
tell application "Music"
  set results to search playlist "Library" for "${safeQuery}"
  if (count of results) is 0 then
    error "No tracks found matching: ${safeName}"
  end if
  play item 1 of results
  set t to current track
  return "Now playing: " & (name of t) & " by " & (artist of t)
end tell`;
  return runAppleScript(script);
}

export interface Playlist {
  name: string;
  kind: string;
  trackCount: number;
}

export async function listPlaylists(): Promise<Playlist[]> {
  const script = `
tell application "Music"
  set output to {}
  set playlistCount to count of every playlist
  repeat with i from 1 to playlistCount
    set p to playlist i
    set pKind to class of p as text
    set pCount to 0
    try
      set pCount to count of tracks of p
    end try
    set end of output to (name of p) & "|||" & pKind & "|||" & (pCount as text)
  end repeat
  set AppleScript's text item delimiters to "<<<>>>"
  return output as text
end tell`;
  const raw = await runAppleScript(script);
  if (!raw) return [];
  return raw.split("<<<>>>").map((record) => {
    const parts = record.split("|||");
    return {
      name: parts[0]?.trim() ?? "",
      kind: parts[1]?.trim() ?? "",
      trackCount: parseInt(parts[2]?.trim() ?? "0", 10),
    };
  });
}

export async function playPlaylist(name: string): Promise<string> {
  const safeName = sanitize(name);
  const script = `
tell application "Music"
  set matched to (every playlist whose name is "${safeName}")
  if (count of matched) is 0 then
    error "Playlist not found: ${safeName}"
  end if
  play item 1 of matched
  return "Now playing playlist: ${safeName}"
end tell`;
  return runAppleScript(script);
}

export async function setLoved(loved: boolean): Promise<string> {
  const script = `
tell application "Music"
  if player state is stopped then
    error "Nothing is currently playing"
  end if
  set t to current track
  set loved of t to ${loved}
  return "Track " & (name of t) & " " & "${loved ? "marked as loved" : "removed from loved"}"
end tell`;
  return runAppleScript(script);
}
