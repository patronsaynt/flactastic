import { useState, useRef } from "react";
import {
  Home,
  Music2,
  ListMusic,
  Download,
  LayoutGrid,
  Activity,
  Settings,
  Search,
  Play,
  Pause,
  SkipBack,
  SkipForward,
  Volume2,
  Shuffle,
  Repeat,
  ChevronRight,
  Clock,
  Disc3,
  Headphones,
  TrendingUp,
  Calendar,
  Star,
} from "lucide-react";
import { AreaChart, Area, ResponsiveContainer, Tooltip, XAxis, PieChart, Pie, Cell } from "recharts";

// ─── Mock Data ───────────────────────────────────────────────────────────────

const recentlyPlayed = [
  { id: 1, title: "My Beautiful Dark Twisted Fantasy", artist: "Kanye West",         shade: 0 },
  { id: 2, title: "GNX",                               artist: "Kendrick Lamar",     shade: 1 },
  { id: 3, title: "Music Baby (Jercy Remix)",           artist: "Jane Remover · Amy", shade: 2 },
  { id: 4, title: "Burn",                               artist: "Destroy · Tallulah", shade: 3 },
  { id: 5, title: "Haunted House",                      artist: "Kxllswxtch",         shade: 4 },
  { id: 6, title: "Upon Loss Singles",                  artist: "Knocked Loose",      shade: 5 },
  { id: 7, title: "Woman Worldwide",                    artist: "Justice",            shade: 6 },
];

// Monochrome gradients — varied lightness and angle to distinguish each cover
const albumGradients = [
  "linear-gradient(135deg, #1c1c1c 0%, #2e2e2e 100%)",
  "linear-gradient(160deg, #111111 0%, #333333 100%)",
  "linear-gradient(110deg, #242424 0%, #181818 100%)",
  "linear-gradient(150deg, #1a1a1a 0%, #3a3a3a 100%)",
  "linear-gradient(120deg, #202020 0%, #141414 100%)",
  "linear-gradient(140deg, #2c2c2c 0%, #161616 100%)",
  "linear-gradient(125deg, #181818 0%, #303030 100%)",
];

const weeklyListeningData = [
  { day: "Mon", minutes: 42 },
  { day: "Tue", minutes: 78 },
  { day: "Wed", minutes: 55 },
  { day: "Thu", minutes: 110 },
  { day: "Fri", minutes: 95 },
  { day: "Sat", minutes: 145 },
  { day: "Sun", minutes: 88 },
];

const topArtists = [
  { name: "Kanye West",     plays: 1247 },
  { name: "Kendrick Lamar", plays: 984  },
  { name: "Jane Remover",   plays: 762  },
  { name: "Justice",        plays: 541  },
  { name: "Knocked Loose",  plays: 388  },
];

const formatData = [
  { label: "FLAC",  pct: 58, sub: "Lossless",        opacity: 0.88 },
  { label: "MP3",   pct: 22, sub: "Lossy",            opacity: 0.32 },
  { label: "AAC",   pct: 10, sub: "Lossy",            opacity: 0.22 },
  { label: "WAV",   pct:  5, sub: "Lossless PCM",     opacity: 0.62 },
  { label: "ALAC",  pct:  3, sub: "Lossless",         opacity: 0.48 },
  { label: "AIFF",  pct:  2, sub: "Lossless PCM",     opacity: 0.38 },
];

const bitDepthData = [
  { label: "24-bit", pct: 61 },
  { label: "16-bit", pct: 36 },
  { label: "32-bit", pct:  3 },
];

const sampleRates = [
  { rate: "192 kHz", count: 48,   tier: "Ultra Hi-Res" },
  { rate: "96 kHz",  count: 312,  tier: "Hi-Res"       },
  { rate: "88.2 kHz",count: 94,   tier: "Hi-Res"       },
  { rate: "48 kHz",  count: 201,  tier: "Studio"       },
  { rate: "44.1 kHz",count: 8411, tier: "CD Quality"   },
];

const topAlbumsWeek = [
  { id: 1, title: "My Beautiful Dark Twisted Fantasy", artist: "Kanye West",     plays: 34, shade: 0, mins: 142 },
  { id: 2, title: "GNX",                               artist: "Kendrick Lamar", plays: 28, shade: 1, mins: 97  },
  { id: 3, title: "Woman Worldwide",                   artist: "Justice",        plays: 21, shade: 6, mins: 88  },
  { id: 4, title: "Burn",                              artist: "Destroy",        plays: 19, shade: 3, mins: 74  },
  { id: 5, title: "Haunted House",                     artist: "Kxllswxtch",    plays: 17, shade: 4, mins: 61  },
  { id: 6, title: "Upon Loss Singles",                 artist: "Knocked Loose",  plays: 14, shade: 5, mins: 52  },
];

const navItems = [
  { label: "Home",       icon: Home       },
  { label: "Collection", icon: Music2     },
  { label: "Playlists",  icon: ListMusic  },
  { label: "Download",   icon: Download   },
  { label: "Organizer",  icon: LayoutGrid },
  { label: "Visualizer", icon: Activity   },
];

// ─── Album Art Placeholder ───────────────────────────────────────────────────

function AlbumArt({ shade, size = "md" }: { shade: number; size?: "sm" | "md" }) {
  const sizeClass = size === "sm" ? "w-10 h-10" : "w-full aspect-square";
  const iconSize  = size === "sm" ? 12 : 20;
  return (
    <div
      className={`${sizeClass} rounded-md flex-shrink-0 relative overflow-hidden`}
      style={{ background: albumGradients[shade % albumGradients.length] }}
    >
      {/* Subtle crosshatch noise */}
      <div
        className="absolute inset-0"
        style={{
          backgroundImage:
            "repeating-linear-gradient(0deg, transparent, transparent 3px, rgba(255,255,255,0.015) 3px, rgba(255,255,255,0.015) 4px)," +
            "repeating-linear-gradient(90deg, transparent, transparent 3px, rgba(255,255,255,0.015) 3px, rgba(255,255,255,0.015) 4px)",
        }}
      />
      <div className="absolute bottom-1.5 right-1.5 opacity-20">
        <Disc3 size={iconSize} color="white" />
      </div>
    </div>
  );
}

// ─── Stat Card ───────────────────────────────────────────────────────────────

function StatCard({
  icon: Icon,
  label,
  value,
  sub,
}: {
  icon: React.ElementType;
  label: string;
  value: string;
  sub?: string;
}) {
  return (
    <div
      className="rounded-xl p-4 flex flex-col gap-3 border border-white/[0.06] relative overflow-hidden"
      style={{ background: "#141414" }}
    >
      {/* Subtle top-edge highlight — macOS glass feel */}
      <div
        className="absolute top-0 left-0 right-0 h-px"
        style={{ background: "linear-gradient(90deg, transparent, rgba(255,255,255,0.07), transparent)" }}
      />
      <div
        className="w-8 h-8 rounded-lg flex items-center justify-center border border-white/[0.06]"
        style={{ background: "#1e1e1e" }}
      >
        <Icon size={14} className="text-white/50" />
      </div>
      <div>
        <div className="text-2xl font-semibold text-white/90 tracking-tight tabular-nums">{value}</div>
        <div className="text-[11px] text-white/35 mt-0.5 uppercase tracking-wider">{label}</div>
        {sub && <div className="text-[11px] text-white/55 mt-1.5">{sub}</div>}
      </div>
    </div>
  );
}

// ─── Main App ────────────────────────────────────────────────────────────────

export default function App() {
  const [activeNav, setActiveNav] = useState("Home");
  const [isPlaying, setIsPlaying] = useState(true);
  const [progress, setProgress] = useState(38);
  const [volume, setVolume] = useState(72);
  const scrollRef = useRef<HTMLDivElement>(null);

  return (
    <div
      className="flex flex-col w-full h-screen overflow-hidden select-none"
      style={{ background: "#0a0a0a", fontFamily: "'Inter', system-ui, sans-serif" }}
    >
      {/* ── Top Nav Bar ── */}
      <div
        className="flex items-center justify-between px-4 h-11 flex-shrink-0"
        style={{
          background: "rgba(10,10,10,0.92)",
          backdropFilter: "blur(24px)",
          borderBottom: "1px solid rgba(255,255,255,0.06)",
        }}
      >
        {/* Left: wordmark */}
        <div className="flex items-center gap-2 w-40">
          <div
            className="w-5 h-5 rounded-full flex items-center justify-center"
            style={{ background: "#222", border: "1px solid rgba(255,255,255,0.12)" }}
          >
            <Music2 size={9} color="rgba(255,255,255,0.7)" />
          </div>
          <span className="text-[10px] font-semibold tracking-[0.18em] uppercase text-white/40">
            FLACtastic
          </span>
        </div>

        {/* Center: nav tabs */}
        <div className="flex items-center gap-0.5">
          {navItems.map(({ label, icon: Icon }) => (
            <button
              key={label}
              onClick={() => setActiveNav(label)}
              className={`flex items-center gap-1.5 px-3 h-7 rounded-md text-[11px] transition-all duration-150 ${
                activeNav === label
                  ? "text-white/90"
                  : "text-white/30 hover:text-white/55"
              }`}
              style={
                activeNav === label
                  ? { background: "rgba(255,255,255,0.08)", border: "1px solid rgba(255,255,255,0.07)" }
                  : {}
              }
            >
              <Icon size={11} />
              {label}
            </button>
          ))}
        </div>

        {/* Right: search + settings */}
        <div className="flex items-center gap-2 w-40 justify-end">
          <div
            className="flex items-center gap-1.5 rounded-md px-2 h-6"
            style={{ background: "#1a1a1a", border: "1px solid rgba(255,255,255,0.06)" }}
          >
            <Search size={9} className="text-white/25" />
            <span className="text-[11px] text-white/25">Search...</span>
          </div>
          <button className="text-white/25 hover:text-white/55 transition-colors">
            <Settings size={13} />
          </button>
        </div>
      </div>

      {/* ── Main Content ── */}
      <div className="flex-1 overflow-y-auto overflow-x-hidden" style={{ scrollbarWidth: "none" }}>

        {/* ── Hero Header ── */}
        <div className="relative px-8 pt-10 pb-8 overflow-hidden">
          {/* Monochrome glow — pure white, extremely subtle */}
          <div
            className="absolute top-0 left-1/3 w-[500px] h-48 rounded-full pointer-events-none"
            style={{
              background: "radial-gradient(ellipse, rgba(255,255,255,0.04) 0%, transparent 70%)",
              filter: "blur(32px)",
            }}
          />

          {/* Top edge line — decorative rule */}
          <div
            className="absolute top-0 left-8 right-8 h-px"
            style={{ background: "linear-gradient(90deg, transparent, rgba(255,255,255,0.06) 30%, rgba(255,255,255,0.06) 70%, transparent)" }}
          />

          <div className="relative">
            <p className="text-[10px] font-medium tracking-[0.2em] uppercase text-white/25 mb-3">
              {new Date().toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric" })}
            </p>
            <h1
              className="font-bold tracking-tight"
              style={{
                fontSize: "clamp(28px, 4vw, 40px)",
                lineHeight: 1.12,
                background: "linear-gradient(170deg, rgba(255,255,255,0.92) 0%, rgba(255,255,255,0.38) 100%)",
                WebkitBackgroundClip: "text",
                WebkitTextFillColor: "transparent",
                backgroundClip: "text",
              }}
            >
              Welcome to your<br />library.
            </h1>
            <p className="text-[12px] text-white/30 mt-3 tracking-wide">
              1,127 albums&ensp;·&ensp;847 hours of music&ensp;·&ensp;Hi-Fi quality
            </p>
          </div>
        </div>

        {/* ── Recently Played ── */}
        <section className="px-8 mb-8">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-[11px] font-semibold text-white/50 uppercase tracking-[0.14em]">Recently Played</h2>
            <button className="flex items-center gap-0.5 text-[11px] text-white/25 hover:text-white/50 transition-colors">
              See all <ChevronRight size={11} />
            </button>
          </div>

          <div
            ref={scrollRef}
            className="flex gap-3 overflow-x-auto pb-1"
            style={{ scrollbarWidth: "none" }}
          >
            {recentlyPlayed.map((album) => (
              <div key={album.id} className="flex-shrink-0 w-36 group cursor-pointer">
                <div className="relative mb-2.5">
                  <AlbumArt shade={album.shade} />
                  <div
                    className="absolute inset-0 flex items-center justify-center rounded-md opacity-0 group-hover:opacity-100 transition-opacity duration-200"
                    style={{ background: "rgba(0,0,0,0.5)" }}
                  >
                    <button
                      className="w-9 h-9 rounded-full flex items-center justify-center transition-transform duration-150 active:scale-95"
                      style={{ background: "rgba(255,255,255,0.88)", border: "1px solid rgba(255,255,255,0.2)" }}
                    >
                      <Play size={13} fill="#0a0a0a" color="#0a0a0a" className="ml-0.5" />
                    </button>
                  </div>
                </div>
                <p className="text-[12px] font-medium text-white/75 truncate leading-tight">{album.title}</p>
                <p className="text-[11px] text-white/30 truncate mt-0.5">{album.artist}</p>
              </div>
            ))}
          </div>
        </section>

        {/* ── Studio Quality Index ── */}
        <section className="px-8 mb-8">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-[11px] font-semibold text-white/50 uppercase tracking-[0.14em]">Studio Quality Index</h2>
              <p className="text-[10px] text-white/20 mt-0.5">Audio fidelity breakdown across your library</p>
            </div>
            <div
              className="flex items-center gap-1.5 px-2.5 py-1 rounded-md"
              style={{ background: "#1a1a1a", border: "1px solid rgba(255,255,255,0.07)" }}
            >
              <span className="text-[10px] text-white/30 uppercase tracking-wider">Score</span>
              <span className="text-[13px] font-semibold text-white/80 tabular-nums">87</span>
              <span className="text-[10px] text-white/25">/ 100</span>
            </div>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-2.5">

            {/* Pie chart card */}
            <div
              className="rounded-xl p-4 flex flex-col"
              style={{ background: "#141414", border: "1px solid rgba(255,255,255,0.06)" }}
            >
              <p className="text-[11px] font-semibold text-white/60 mb-1">File Format Distribution</p>
              <p className="text-[10px] text-white/20 mb-3">9,066 total files</p>
              <div className="flex items-center gap-4">
                {/* Pie */}
                <div className="w-28 h-28 flex-shrink-0">
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie
                        data={formatData}
                        dataKey="pct"
                        cx="50%"
                        cy="50%"
                        innerRadius="52%"
                        outerRadius="80%"
                        strokeWidth={0}
                        paddingAngle={1.5}
                      >
                        {formatData.map((f, i) => (
                          <Cell key={`cell-${i}`} fill={`rgba(255,255,255,${f.opacity})`} />
                        ))}
                      </Pie>
                      <Tooltip
                        contentStyle={{
                          background: "#1c1c1c",
                          border: "1px solid rgba(255,255,255,0.08)",
                          borderRadius: 8,
                          fontSize: 11,
                          color: "rgba(255,255,255,0.75)",
                        }}
                        formatter={(v: number, _: string, entry: { payload: { label: string; sub: string } }) =>
                          [`${v}% — ${entry.payload.sub}`, entry.payload.label]
                        }
                      />
                    </PieChart>
                  </ResponsiveContainer>
                </div>
                {/* Legend */}
                <div className="flex flex-col gap-1.5 flex-1">
                  {formatData.map((f) => (
                    <div key={f.label} className="flex items-center gap-2">
                      <div
                        className="w-1.5 h-1.5 rounded-full flex-shrink-0"
                        style={{ background: `rgba(255,255,255,${f.opacity})` }}
                      />
                      <span className="text-[10px] text-white/55 w-8 font-medium">{f.label}</span>
                      <span className="text-[10px] text-white/25 tabular-nums">{f.pct}%</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>

            {/* Bit depth + sample rates */}
            <div
              className="rounded-xl p-4"
              style={{ background: "#141414", border: "1px solid rgba(255,255,255,0.06)" }}
            >
              <p className="text-[11px] font-semibold text-white/60 mb-3">Bit Depth</p>
              <div className="flex flex-col gap-2 mb-5">
                {bitDepthData.map((b) => (
                  <div key={b.label}>
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-[11px] text-white/55">{b.label}</span>
                      <span className="text-[10px] text-white/25 tabular-nums">{b.pct}%</span>
                    </div>
                    <div className="h-px rounded-full" style={{ background: "rgba(255,255,255,0.08)" }}>
                      <div
                        className="h-full rounded-full"
                        style={{ width: `${b.pct}%`, background: `rgba(255,255,255,${0.2 + b.pct / 200})` }}
                      />
                    </div>
                  </div>
                ))}
              </div>
              <div className="flex gap-3">
                <div className="flex-1 rounded-lg p-2.5" style={{ background: "#1a1a1a", border: "1px solid rgba(255,255,255,0.05)" }}>
                  <p className="text-[17px] font-semibold text-white/80 tabular-nums">63%</p>
                  <p className="text-[9px] text-white/30 uppercase tracking-wider mt-0.5">Lossless</p>
                </div>
                <div className="flex-1 rounded-lg p-2.5" style={{ background: "#1a1a1a", border: "1px solid rgba(255,255,255,0.05)" }}>
                  <p className="text-[17px] font-semibold text-white/80 tabular-nums">454</p>
                  <p className="text-[9px] text-white/30 uppercase tracking-wider mt-0.5">Hi-Res files</p>
                </div>
              </div>
            </div>

            {/* Sample rate breakdown */}
            <div
              className="rounded-xl p-4"
              style={{ background: "#141414", border: "1px solid rgba(255,255,255,0.06)" }}
            >
              <p className="text-[11px] font-semibold text-white/60 mb-3">Sample Rates</p>
              <div className="flex flex-col gap-2.5">
                {sampleRates.map((s, i) => {
                  const maxCount = sampleRates[sampleRates.length - 1].count;
                  const pct = Math.round((s.count / maxCount) * 100);
                  const barW = Math.max(4, Math.round((s.count / maxCount) * 100));
                  return (
                    <div key={s.rate} className="flex items-center gap-2.5">
                      <div className="w-14 flex-shrink-0">
                        <p className="text-[10px] font-medium text-white/60 tabular-nums">{s.rate}</p>
                        <p className="text-[9px] text-white/20 mt-0.5">{s.tier}</p>
                      </div>
                      <div className="flex-1 h-px rounded-full" style={{ background: "rgba(255,255,255,0.07)" }}>
                        <div
                          className="h-full rounded-full"
                          style={{ width: `${barW}%`, background: `rgba(255,255,255,${0.6 - i * 0.1})` }}
                        />
                      </div>
                      <span className="text-[10px] text-white/25 w-8 text-right tabular-nums">{s.count.toLocaleString()}</span>
                    </div>
                  );
                })}
              </div>
              {/* Avg bitrate callout */}
              <div
                className="mt-4 rounded-lg p-2.5 flex items-center justify-between"
                style={{ background: "#1a1a1a", border: "1px solid rgba(255,255,255,0.05)" }}
              >
                <div>
                  <p className="text-[9px] text-white/25 uppercase tracking-wider">Avg Bitrate</p>
                  <p className="text-[15px] font-semibold text-white/75 tabular-nums mt-0.5">1,247 <span className="text-[10px] font-normal text-white/30">kbps</span></p>
                </div>
                <div className="text-right">
                  <p className="text-[9px] text-white/25 uppercase tracking-wider">Dynamic Range</p>
                  <p className="text-[15px] font-semibold text-white/75 tabular-nums mt-0.5">DR12 <span className="text-[10px] font-normal text-white/30">avg</span></p>
                </div>
              </div>
            </div>

          </div>
        </section>

        {/* ── Listening Stats ── */}
        <section className="px-8 mb-8">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-[11px] font-semibold text-white/50 uppercase tracking-[0.14em]">Your Listening Stats</h2>
            <span className="text-[11px] text-white/25">All time</span>
          </div>

          {/* Stat cards */}
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-2.5 mb-4">
            <StatCard icon={Clock}      label="Hours Listened"    value="847h"   sub="↑ 12h this week" />
            <StatCard icon={Music2}     label="Tracks Played"     value="12.4k"  sub="All time"        />
            <StatCard icon={Disc3}      label="Albums in Library" value="1,127"  sub="+4 this month"   />
            <StatCard icon={Headphones} label="Sessions"          value="3,891"  sub="Avg 13 min"      />
            <StatCard icon={Star}       label="Top Genre"         value="Hip-Hop" sub="38% of plays"   />
            <StatCard icon={TrendingUp} label="Current Streak"    value="47 days" sub="Personal best"  />
          </div>

          {/* Chart + Top Artists */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-2.5">

            {/* Weekly chart */}
            <div
              className="lg:col-span-2 rounded-xl p-4"
              style={{ background: "#141414", border: "1px solid rgba(255,255,255,0.06)" }}
            >
              <div
                className="absolute top-0 left-0 right-0 h-px"
                style={{ background: "linear-gradient(90deg, transparent, rgba(255,255,255,0.06), transparent)" }}
              />
              <div className="flex items-center justify-between mb-3">
                <div>
                  <p className="text-[11px] font-semibold text-white/60">Weekly Listening</p>
                  <p className="text-[10px] text-white/25 mt-0.5">Minutes per day</p>
                </div>
                <div className="flex items-center gap-1.5">
                  <Calendar size={10} className="text-white/20" />
                  <span className="text-[10px] text-white/25">This week</span>
                </div>
              </div>
              <div className="h-28">
                <ResponsiveContainer width="100%" height="100%">
                  <AreaChart data={weeklyListeningData} margin={{ top: 2, right: 2, left: -30, bottom: 0 }}>
                    <defs>
                      <linearGradient id="flactastic-mono-grad" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%"   stopColor="rgba(255,255,255,1)" stopOpacity={0.12} />
                        <stop offset="100%" stopColor="rgba(255,255,255,1)" stopOpacity={0.0}  />
                      </linearGradient>
                    </defs>
                    <XAxis
                      dataKey="day"
                      tick={{ fontSize: 10, fill: "rgba(255,255,255,0.25)" }}
                      axisLine={false}
                      tickLine={false}
                    />
                    <Tooltip
                      contentStyle={{
                        background: "#1c1c1c",
                        border: "1px solid rgba(255,255,255,0.08)",
                        borderRadius: 8,
                        fontSize: 11,
                        color: "rgba(255,255,255,0.75)",
                      }}
                      formatter={(v: number) => [`${v} min`, "Listened"]}
                      cursor={{ stroke: "rgba(255,255,255,0.08)", strokeWidth: 1 }}
                    />
                    <Area
                      type="monotone"
                      dataKey="minutes"
                      stroke="rgba(255,255,255,0.5)"
                      strokeWidth={1.5}
                      fill="url(#flactastic-mono-grad)"
                      dot={false}
                      activeDot={{ r: 3, fill: "rgba(255,255,255,0.9)", stroke: "#0a0a0a", strokeWidth: 2 }}
                    />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
            </div>

            {/* Top Artists */}
            <div
              className="rounded-xl p-4"
              style={{ background: "#141414", border: "1px solid rgba(255,255,255,0.06)" }}
            >
              <p className="text-[11px] font-semibold text-white/60 mb-4">Top Artists</p>
              <div className="flex flex-col gap-3">
                {topArtists.map((artist, i) => {
                  const pct = Math.round((artist.plays / topArtists[0].plays) * 100);
                  // Fade each rank slightly — top is brightest
                  const textOpacity = 0.75 - i * 0.1;
                  const barOpacity  = 0.55 - i * 0.08;
                  return (
                    <div key={artist.name} className="flex items-center gap-2.5">
                      <span
                        className="text-[10px] w-3 text-right tabular-nums"
                        style={{ color: `rgba(255,255,255,${0.2 + i * 0.02})` }}
                      >
                        {i + 1}
                      </span>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center justify-between mb-1.5">
                          <span className="text-[11px] truncate" style={{ color: `rgba(255,255,255,${textOpacity})` }}>
                            {artist.name}
                          </span>
                          <span className="text-[10px] ml-2 flex-shrink-0 tabular-nums" style={{ color: "rgba(255,255,255,0.22)" }}>
                            {artist.plays.toLocaleString()}
                          </span>
                        </div>
                        <div className="h-px rounded-full" style={{ background: "rgba(255,255,255,0.08)" }}>
                          <div
                            className="h-full rounded-full"
                            style={{
                              width: `${pct}%`,
                              background: `rgba(255,255,255,${barOpacity})`,
                            }}
                          />
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>

          </div>
        </section>

        {/* ── Top Albums This Week ── */}
        <section className="px-8 mb-8">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-[11px] font-semibold text-white/50 uppercase tracking-[0.14em]">Top Albums This Week</h2>
            <button className="flex items-center gap-0.5 text-[11px] text-white/25 hover:text-white/50 transition-colors">
              See all <ChevronRight size={11} />
            </button>
          </div>

          <div className="grid grid-cols-1 gap-px" style={{ background: "rgba(255,255,255,0.05)", borderRadius: 12, overflow: "hidden" }}>
            {topAlbumsWeek.map((album, i) => {
              const maxPlays = topAlbumsWeek[0].plays;
              const pct = Math.round((album.plays / maxPlays) * 100);
              return (
                <div
                  key={album.id}
                  className="flex items-center gap-4 px-4 py-3 group cursor-pointer transition-colors"
                  style={{ background: "#111111" }}
                  onMouseEnter={(e) => (e.currentTarget.style.background = "#161616")}
                  onMouseLeave={(e) => (e.currentTarget.style.background = "#111111")}
                >
                  {/* Rank */}
                  <span
                    className="text-[12px] font-semibold tabular-nums w-4 text-right flex-shrink-0"
                    style={{ color: i === 0 ? "rgba(255,255,255,0.7)" : "rgba(255,255,255,0.2)" }}
                  >
                    {i + 1}
                  </span>

                  {/* Art */}
                  <div className="relative flex-shrink-0">
                    <AlbumArt shade={album.shade} size="sm" />
                    <div
                      className="absolute inset-0 flex items-center justify-center rounded-md opacity-0 group-hover:opacity-100 transition-opacity"
                      style={{ background: "rgba(0,0,0,0.55)" }}
                    >
                      <Play size={10} fill="white" color="white" className="ml-0.5" />
                    </div>
                  </div>

                  {/* Title + artist */}
                  <div className="flex-1 min-w-0">
                    <p className="text-[12px] font-medium text-white/75 truncate">{album.title}</p>
                    <p className="text-[10px] text-white/30 truncate mt-0.5">{album.artist}</p>
                  </div>

                  {/* Progress bar (relative play count) */}
                  <div className="hidden md:flex items-center gap-3 w-40">
                    <div className="flex-1 h-px rounded-full" style={{ background: "rgba(255,255,255,0.07)" }}>
                      <div
                        className="h-full rounded-full transition-all"
                        style={{ width: `${pct}%`, background: "rgba(255,255,255,0.35)" }}
                      />
                    </div>
                  </div>

                  {/* Stats */}
                  <div className="flex items-center gap-4 flex-shrink-0 text-right">
                    <div className="hidden sm:block">
                      <p className="text-[11px] text-white/55 tabular-nums">{album.plays} plays</p>
                      <p className="text-[10px] text-white/20 tabular-nums">{album.mins} min</p>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </section>

      </div>

      {/* ── Bottom Player Bar ── */}
      <div
        className="flex-shrink-0 px-4 flex items-center h-16 gap-4"
        style={{
          background: "rgba(8,8,8,0.96)",
          backdropFilter: "blur(24px)",
          borderTop: "1px solid rgba(255,255,255,0.06)",
        }}
      >
        {/* Now playing */}
        <div className="flex items-center gap-3 w-56 flex-shrink-0">
          <AlbumArt shade={0} size="sm" />
          <div className="min-w-0">
            <p className="text-[11px] font-medium text-white/75 truncate">How We Do - Radio Edit</p>
            <p className="text-[10px] text-white/30 truncate mt-0.5">Montague · Sicerae</p>
          </div>
        </div>

        {/* Controls */}
        <div className="flex-1 flex flex-col items-center gap-1.5">
          <div className="flex items-center gap-4">
            <button className="text-white/25 hover:text-white/60 transition-colors"><Shuffle    size={13} /></button>
            <button className="text-white/40 hover:text-white/75 transition-colors"><SkipBack   size={15} /></button>
            <button
              onClick={() => setIsPlaying(!isPlaying)}
              className="w-7 h-7 rounded-full flex items-center justify-center transition-all hover:scale-105 active:scale-95"
              style={{ background: "rgba(255,255,255,0.9)" }}
            >
              {isPlaying
                ? <Pause size={11} fill="#0a0a0a" color="#0a0a0a" />
                : <Play  size={11} fill="#0a0a0a" color="#0a0a0a" className="ml-0.5" />}
            </button>
            <button className="text-white/40 hover:text-white/75 transition-colors"><SkipForward size={15} /></button>
            <button className="text-white/25 hover:text-white/60 transition-colors"><Repeat      size={13} /></button>
          </div>

          {/* Progress */}
          <div className="flex items-center gap-2 w-full max-w-sm">
            <span className="text-[10px] text-white/25 w-8 text-right tabular-nums">1:47</span>
            <div className="flex-1 relative h-px rounded-full" style={{ background: "rgba(255,255,255,0.12)" }}>
              <div className="h-full rounded-full" style={{ width: `${progress}%`, background: "rgba(255,255,255,0.75)" }} />
              <input
                type="range" min={0} max={100} value={progress}
                onChange={(e) => setProgress(Number(e.target.value))}
                className="absolute inset-0 w-full opacity-0 cursor-pointer"
                style={{ height: "12px", top: "-6px" }}
              />
            </div>
            <span className="text-[10px] text-white/25 w-8 tabular-nums">4:43</span>
          </div>
        </div>

        {/* Volume */}
        <div className="flex items-center gap-2 w-32 flex-shrink-0 justify-end">
          <Volume2 size={12} className="text-white/25" />
          <div className="relative h-px w-20 rounded-full" style={{ background: "rgba(255,255,255,0.12)" }}>
            <div className="h-full rounded-full" style={{ width: `${volume}%`, background: "rgba(255,255,255,0.45)" }} />
            <input
              type="range" min={0} max={100} value={volume}
              onChange={(e) => setVolume(Number(e.target.value))}
              className="absolute inset-0 w-full opacity-0 cursor-pointer"
              style={{ height: "12px", top: "-6px" }}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
