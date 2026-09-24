# Ororo API notes

What the ororo.tv backend exposes, as observed in September 2026. None of this
is documented by Ororo; it was worked out from their official Kodi addon
(`plugin.video.ororotv` 4.0.4) and from live responses.

## Hosts

| Host | Purpose |
| --- | --- |
| `front.ororo.tv` | JSON API and subtitle files. Served straight from nginx, not behind Cloudflare. |
| `front.ororo-mirror.tv` | Mirror of the above, for regions where the main domain is blocked. Same data and ETags. |
| `static-*.ororo.tv`, `edge-*.ororo.tv` | Video delivery (Nimble Streamer). About 10 edge servers across the US, EU, Asia and Russia. |
| `uploads.ororo-mirror.tv` | Posters and backdrops. |
| `ororo.tv` | The website, behind Cloudflare with bot checks. Not used by this app. |

## Authentication

HTTP Basic auth with the account email and password on every request. There
is no token or session to manage.

- Wrong credentials: `401` with an empty body.
- Cheap credential check: `GET /api/v2/shows/0` answers `401` for bad
  credentials and `404` for good ones.

## Endpoints

Base URL: `https://front.ororo.tv/api/v2`. Send `Accept: application/json`.

| Endpoint | Returns |
| --- | --- |
| `GET /shows` | `{ "shows": [Show] }`: the whole catalog (about 4,000 shows, 3 MB, 1 MB gzipped). No pagination. |
| `GET /shows/:id` | A `Show` plus `seasons` (count) and `episodes: [Episode]`. |
| `GET /episodes/:id` | An `Episode` plus `url`, `download_url`, `subtitles`, `show_name`. |
| `GET /movies` | `{ "movies": [Movie] }`: the whole catalog (about 7,900 movies, 5 MB, 1.8 MB gzipped). |
| `GET /movies/:id` | A `Movie` plus `url`, `download_url`, `subtitles`, `trailer`, `slug`. |
| `GET /balancer/resolve_host` | `{ "host": "static-us2.ororo.tv" }`: suggested video edge server. |

There is no search, history, favorites, account or genre endpoint. The website
has those behind a separate cookie-authenticated API (`/api/frontend/*`), which
this app does not use. Search, history and My List are therefore done on the
device.

### Status codes

| Status | Meaning |
| --- | --- |
| `304` | Catalog unchanged since the `If-None-Match` ETag you sent. |
| `401` | Bad or missing credentials. |
| `402` | Free account's daily limit reached (30 minutes of video per rolling 24 hours). |
| `404` | `{"status":404,"error":"Not Found"}` |

### Caching

List responses carry a weak `ETag` and `Cache-Control: max-age=0, private,
must-revalidate`. Sending the ETag back as `If-None-Match` returns an empty
`304` when nothing changed. Gzip is supported.

## Shapes

Fields marked `?` were null for at least one title in the live catalog.

**Show**

```
id: Int                 name: String            slug: String
year: String            desc: String            ended: Bool
length: Int?            (typical episode minutes)
imdb_id: String         imdb_rating: Double?    tmdb_id: String?
kinopoisk_id: String?   myshows_id: Int?
array_genres: [String]  array_countries: [String]  (ISO country codes)
poster_thumb: String    backdrop_url: String?
newest_video: Int       (Unix time of the latest episode)
updated_at: Int         user_popularity: Int
```

**Episode** (inside `GET /shows/:id`)

```
id: Int        season: Int        number: String  ("4", sent as a string)
name: String?  plot: String?      airdate: String ("2025-02-21")
resolution: String ("HD" | "SD")  updated_at: Int
myshows_id: Int?   watched_media_count: Int
info: { original, smil, thumbs }
versions: { "240p": path, ..., "1080p": path }   (unsigned; 403 if requested)
```

**Movie**

```
id, name, year, desc, length: Int, imdb_id, imdb_rating: Double?,
array_genres, array_countries, poster_thumb, backdrop_url?,
resolution, updated_at
```

**Playback fields** (only on `GET /episodes/:id` and `GET /movies/:id`)

```
url:          https://static-us2.ororo.tv/.../file.smil/playlist_fmp4.m3u8?wmsAuthSign=...
download_url: https://static-us2.ororo.tv/.../file_1080p.mp4?attachment=true&wmsAuthSign=...
subtitles:    [{ "lang": "en", "url": "https://front.ororo.tv/uploads/subtitle/file/.../x.vtt" }]
trailer:      YouTube video id (movies only)
```

## Playback

- `url` is an HLS master playlist (version 6, fMP4 segments, H.264 + AAC) with
  five renditions from 240p to 1080p. AVPlayer plays it directly.
- Stream URLs carry a `wmsAuthSign` token tied to the account and media, valid
  for 1,920 minutes (32 hours). Fetch a fresh one right before playing.
- The HLS stream contains no subtitle tracks. Subtitles are separate WebVTT
  files, public and unsigned, typically in 5 to 10 languages per title.
