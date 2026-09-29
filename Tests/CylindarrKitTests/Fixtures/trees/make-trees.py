# Synthetic Pinchflat and TubeSync trees with the quirks of real ones.
import random
random.seed(7)
look = ["’", "：", "？", "＂", "“", "”", "｜", "‘", "—", "⧸", " "]
words = ["Harbour", "Lights", "Tide", "Keeper", "Night", "Signal", "Fog", "Pier", "Beacon", "Current", "Salt", "Chart",
         "Anchor", "Rope", "Storm", "Glass", "Lamp", "Shore", "Wake", "North", "Bell", "Buoy", "Map", "Cove"]
def title(i):
    w = random.sample(words, 4)
    t = f"The {w[0]} and the {w[1]} of {w[2]} {w[3]}"
    c = look[i % len(look)]
    if c in "：？｜—⧸":
        t = t.replace(" and", c + " and", 1) if c != "？" else t + "？ Part " + str(i % 5 + 1)
    elif c in "’‘":
        t = t.replace("The ", f"The Keeper{c}s ", 1)
    elif c in "＂“”":
        t = t + f" {c}Live{c}"
    else:
        t = t.replace(" of ", " of" + c, 1)
    return t

tree = []
def episode(show, stem, srt=True, nfo=True, thumb="-thumb.jpg"):
    base = f"shows/{show}/{stem}"
    tree.extend([base + ".mp4", base + ".info.json"])
    if nfo: tree.append(base + ".nfo")
    if thumb: tree.append(base + thumb)
    if srt: tree.append(base + ".en.srt")

days = set()
for i in range(60):
    y = 2016 + i % 11
    m, d = 1 + (i * 5) % 12, 1 + (i * 7) % 28
    while (y, m, d) in days or (y, m, d) == (2017, 7, 18):
        d = d % 28 + 1
    days.add((y, m, d))
    episode("Harbour Lights", f"s{y}e{m:02d}{d:02d} - {title(i)}", srt=i % 9 != 0)
for t in ["Reading the Harbour Master's Log", "Visiting the Lighthouse at Night, in 4K", "Who Keeps the Lights On？ The Keepers' Union"]:
    episode("Harbour Lights", f"s2017e0718 - {t}")
for i, t in enumerate(["Cogs", "Springs", "Escapements", "Pendulums", "Winding Keys"]):
    episode("Quiet Machines", f"s202{i}e03{10 + i} - How {t} Work")
tree += ["shows/Quiet Machines/poster.jpg", "shows/Quiet Machines/tvshow.nfo"]
for i, t in enumerate(["The Archive： Part One", "The Archive： Part Two", "Opening the Boxes"]):
    episode("Old Archive", f"s201{i + 1}e10{i + 1:02d} - {t}")
b = "shows/Old Archive/s2016e0517 - The Archive (Original Series)"
tree += [b + ".en.srt", b + ".en.temp.srt.concat", b + ".info.json", b + ".jpg", b + ".mp4", b + ".temp.mp4"]
episode("Old Archive", "s2016e0519 - The Archive： Revisited", srt=False)
episode("Grab List", "s2019e1220 - A Lecture on Speaking")
episode("Grab List", "s2009e1110 - A Full Lecture on Sleep (Complete)")
episode("Grab List", "s2021e0405 - Building a Wooden Boat")
open("pinchflat.txt", "w").write("\n".join(sorted(tree)) + "\n")

ts = ["A Concert Recording (Live 2021).mkv", "Conference_Keynote_2021.mp4", "A Documentary About Boats (1984).mp4", ".DS_Store",
      "Live Set 🎸 Full Show.mkv", "Talk 2023 - Rendering pipelines, start to finish.mp4", "Opening Keynote, Day One.webm"]
vids = [("2010-04-20", "the-first-short", "Qm4TzH8vK2a", "720p-vp09-mp4a", True),
        ("2011-02-02", "lanterns-part-2-original-series-2011", "Hb2Wq9Lr0Ts", "720p-vp09-mp4a", True),
        ("2014-01-24", "episode-one-premise", "-aB3dE5fG7h", "1080p-avc1-mp4a", True),
        ("2015-06-17", "episode-three-teaser", "3Hk_mN9-pq1", "1080p-avc1-mp4a", False),
        ("2015-11-10", "becoming-your-own-fan", "g8Yt2Pq4Ls0", "1080p-vp9-mp4a", False),
        ("2016-01-27", "how-i-write-my-notes-and-drafts", "Vr5Nq2Lw8Kz", "1080p-vp09-mp4a", False),
        ("2020-06-30", "lanterns-reality", "Kt3Wq8Zp1Ma", "1080p-vp09-mp4a", True),
        ("2023-03-21", "lanterns-complete-updated-2023-edition", "Zc9XyT3nQeA", "premium-vp09-mp4a", False),
        ("2024-03-15", "beat-the-blank-page", "7Rb_kLp2Wd0", "1080p-vp09-mp4a", False)]
for day, slug, vid, fmt, vtt in vids:
    b = f"video/Paper Lanterns/{day}_paper-lanterns_{slug}_{vid}_{fmt}"
    ts += [b + ".mkv", b + ".nfo"] + ([b + ".en.vtt"] if vtt else [])
b = "video/Saved/2018-05-29_saved-to-tubesync-playlist_teaching-an-old-console-new-tricks_Wp4Xs7Nb2Qe_premium-vp09-mp4a"
ts += [b + ".en.vtt", b + ".mkv", b + ".nfo"]
open("tubesync.txt", "w").write("\n".join(sorted(ts)) + "\n")
