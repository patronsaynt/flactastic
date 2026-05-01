import { Album, Artist, CoverArtwork, LyricLine, Playlist, Track } from '../../types.js'
import { SIZES } from './constants.js'

export enum DeezerFormat {
	MP3_128 = 1,
	MP3_320 = 3,
	FLAC = 9
}

export interface DeezerLoginResponse {
	error?: {
		type: string
		message: string
	}
}

export interface DeezerMediaResponse {
	data: [
		{
			media: [
				{
					sources: [
						{
							url: string
						}
					]
				}
			]
		}
	]
}

export interface DeezerUserData {
	USER: {
		USER_ID: number
		EXPLICIT_CONTENT_LEVEL: string
		OPTIONS: {
			license_token: string
			web_hq: boolean
			web_lossless: boolean
		}
		SETTING: {
			global: {
				language: string
			}
		}
	}
	OFFER_ID: number
	COUNTRY: string
	checkForm: string
}

export interface DeezerArtist {
	ART_ID: string
	ART_NAME: string
	ART_PICTURE: string
}

export function parseArtist(
	artist: DeezerArtist,
	tracks?: DeezerTrack[],
	albums?: DeezerAlbum[]
): Artist {
	let pictures
	if (artist.ART_PICTURE)
		pictures = SIZES.map(
			(s) =>
				`https://e-cdns-images.dzcdn.net/images/artist/${artist.ART_PICTURE}/${s}x${s}-000000-80-0-0.jpg`
		)

	let parsedTracks
	if (tracks) parsedTracks = tracks.map((t) => parseTrack(t))

	let parsedAlbums
	if (albums) parsedAlbums = albums.map(parseAlbum)

	return {
		id: artist.ART_ID,
		url: `https://www.deezer.com/artist/${artist.ART_ID}`,
		pictures,
		name: artist.ART_NAME,
		tracks: parsedTracks,
		albums: parsedAlbums
	}
}

export interface DeezerAlbum {
	ALB_ID: string
	ALB_TITLE: string
	ALB_PICTURE: string
	ARTISTS?: DeezerArtist[]
	ORIGINAL_RELEASE_DATE?: string
	NUMBER_TRACK?: string
	COPYRIGHT?: string
	UPC?: string
	LABEL_NAME?: string
}

export function parseAlbum(album: DeezerAlbum): Album {
	const data: Album = {
		title: album.ALB_TITLE,
		id: album.ALB_ID,
		url: `https://www.deezer.com/album/${album.ALB_ID}`,
		trackCount: album.NUMBER_TRACK ? parseInt(album.NUMBER_TRACK) : undefined,
		releaseDate: album.ORIGINAL_RELEASE_DATE ? new Date(album.ORIGINAL_RELEASE_DATE) : undefined,
		coverArtwork: parseArtwork(album.ALB_PICTURE),
		artists: album.ARTISTS ? album.ARTISTS.map((a) => parseArtist(a)) : undefined,
		label: album.LABEL_NAME
	}

	if (album.COPYRIGHT) data.copyright = album.COPYRIGHT
	if (album.UPC) data.upc = album.UPC

	return data
}

export interface DeezerTrack {
	SNG_ID: string
	SNG_TITLE: string
	VERSION: string
	EXPLICIT_LYRICS: '0' | '1'
	TRACK_NUMBER: string
	DISK_NUMBER: string
	ARTISTS: DeezerArtist[]
	ISRC: string
	SNG_CONTRIBUTORS: { [role: string]: string[] }
	ALB_ID: string
	ALB_TITLE: string
	ALB_PICTURE: string
	DURATION: string
	AVAILABLE_COUNTRIES?: { STREAM_ADS?: string }
	COPYRIGHT: string

	TRACK_TOKEN: string
	TRACK_TOKEN_EXPIRE: number
	MD5_ORIGIN: string
	MEDIA_VERSION: string

	FILESIZE_MP3_320: string
	FILESIZE_FLAC: string

	FALLBACK?: DeezerTrack
}

export interface DeezerLyrics {
	LYRICS_ID: string
	LYRICS_SYNC_JSON: DeezerSyncedLine[]
	LYRICS_TEXT: string
}

export interface DeezerSyncedLine {
	lrc_timestamp?: string
	milliseconds?: string
	duration?: string
	line: string
}

export function parseTrack(track: DeezerTrack, lyricsData?: DeezerLyrics): Track {
	const addt: {
		regions?: string[]
		copyright?: string
		producers?: string[]
		composers?: string[]
		lyricists?: string[]
	} = {}

	if (track?.AVAILABLE_COUNTRIES?.STREAM_ADS)
		addt.regions = [...track.AVAILABLE_COUNTRIES.STREAM_ADS]
	if (track?.COPYRIGHT) addt.copyright = track.COPYRIGHT
	if (track.SNG_CONTRIBUTORS?.producer) addt.producers = track.SNG_CONTRIBUTORS?.producer
	if (track.SNG_CONTRIBUTORS?.composer) addt.composers = track.SNG_CONTRIBUTORS?.composer
	if (track.SNG_CONTRIBUTORS?.composer) addt.lyricists = track.SNG_CONTRIBUTORS?.lyricist

	let lyrics
	if (lyricsData) {
		const lines: LyricLine[] = []

		const syncedLyrics = lyricsData.LYRICS_SYNC_JSON
		if (syncedLyrics) {
			let lastLineEnd = 0
			for (const line of syncedLyrics) {
				if (!line.line) {
					const lastLine = lines[lines.length - 1]
					if (lastLine) lastLine.endTimeMs = lastLineEnd
					continue
				}

				lines.push({
					text: line.line,
					startTimeMs: parseInt(line.milliseconds!)
				})
				lastLineEnd = parseInt(line.milliseconds!) + parseInt(line.duration!)
			}
		} else {
			lines.push({
				text: lyricsData.LYRICS_TEXT
			})
		}

		lyrics = {
			id: lyricsData.LYRICS_ID,
			source: 'deezer',
			lines
		}
	}

	return {
		title: track.VERSION ? `${track.SNG_TITLE} ${track.VERSION}` : track.SNG_TITLE,
		id: track.SNG_ID,
		url: `https://www.deezer.com/track/${track.SNG_ID}`,
		explicit: track.EXPLICIT_LYRICS == '1',
		trackNumber: parseInt(track.TRACK_NUMBER),
		discNumber: parseInt(track.DISK_NUMBER),
		artists: track.ARTISTS.map((a) => parseArtist(a)),
		isrc: track.ISRC,
		album: parseAlbum({
			ALB_ID: track.ALB_ID,
			ALB_PICTURE: track.ALB_PICTURE,
			ALB_TITLE: track.ALB_TITLE
		}),
		durationMs: parseInt(track.DURATION) * 1e3,
		coverArtwork: parseArtwork(track.ALB_PICTURE),
		lyrics,
		...addt
	}
}

export function parseArtwork(picture: string): CoverArtwork[] {
	return SIZES.map((size) => ({
		url: `https://e-cdns-images.dzcdn.net/images/cover/${picture}/${size}x${size}-000000-80-0-0.jpg`,
		height: size,
		width: size
	}))
}

export interface DeezerPlaylistMetadata {
	PLAYLIST_ID: string
	TITLE: string
	DESCRIPTION: string
	PLAYLIST_PICTURE: string
	DURATION: number
	NB_SONG: number
}

export function parsePlaylistMetadata(raw: DeezerPlaylistMetadata) {
	return <Playlist>{
		id: raw.PLAYLIST_ID,
		title: raw.TITLE,
		url: `https://www.deezer.com/playlist/${raw.PLAYLIST_ID}`,
		coverArtwork: parseArtwork(raw.PLAYLIST_PICTURE),
		trackCount: raw.NB_SONG
	}
}
