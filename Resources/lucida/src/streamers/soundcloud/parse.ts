import { Artist, Album, Track } from '../../types.js'
import { spawn } from 'child_process'
import { fetch } from 'undici'
import { imageSize as sizeOf } from 'image-size'
import os from 'node:os'
import fs from 'node:fs'
import path from 'node:path'

async function parseCoverArtwork(url: string) {
	const resp = await fetch(url)
	if (!resp.body) throw new Error('No body on image')
	const body = await resp.arrayBuffer()
	const dimensions = sizeOf(new Uint8Array(body))
	if (!dimensions.width || !dimensions.height) throw new Error(`Couldn't get dimensions`)
	return {
		url,
		width: dimensions.width,
		height: dimensions.height
	}
}

export interface RawArtist {
	id: number
	username: string
	full_name: string
	avatar_url?: string
	permalink_url: string
	kind: 'user'
}

export interface Headers {
	Authorization?: string
	'User-Agent': string
}

export async function parseArtist(raw: RawArtist): Promise<Artist> {
	const artist: Artist = {
		id: raw.id,
		url: raw.permalink_url,
		name: raw.username
	}
	if (raw.avatar_url) {
		artist.pictures = [raw.avatar_url, raw.avatar_url?.replace('-large', '-original')]
	}
	return artist
}

export interface RawAlbum {
	title: string
	id: number
	permalink_url: string
	tracks: RawTrack[]
	track_count: number
	release_date: string
	user: RawArtist
	user_id: number | string
	kind: 'playlist'
}

export async function parseAlbum(raw: RawAlbum): Promise<Album> {
	const album: Album = {
		id: raw.id,
		title: raw.title,
		url: raw.permalink_url,
		trackCount: raw.track_count,
		releaseDate: new Date(raw.release_date),
		artists: [await parseArtist(raw.user)]
	}
	if (raw.tracks?.[0]?.artwork_url != undefined) {
		album.coverArtwork = [await parseCoverArtwork(raw?.tracks?.[0]?.artwork_url)]
	}
	return album
}

export interface RawTrack {
	media?: {
		transcodings?: { duration: number }[]
	}
	kind: 'track'
	id: number | string
	title: string
	duration: number
	created_at: string
	full_duration: number
	permalink_url: string
	artwork_url?: string
	user: RawArtist
	last_modified: string
	description: string
	user_id: number | string
}

export async function parseTrack(raw: RawTrack): Promise<Track> {
	const track: Track = {
		id: raw.id,
		title: raw.title,
		url: raw.permalink_url,
		artists: [await parseArtist(raw.user)],
		durationMs: raw.full_duration || raw.media?.transcodings?.[0]?.duration,
		releaseDate: new Date(raw.created_at),
		description: raw.description
	}

	if (raw?.artwork_url != undefined)
		track.coverArtwork = [await parseCoverArtwork(raw?.artwork_url)]

	return track
}

export async function parseHls(url: string, container: string): Promise<NodeJS.ReadableStream> {
	const folder = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'lucida'))

	return new Promise(function (resolve, reject) {
		const ffmpegProc = spawn('ffmpeg', [
			'-hide_banner',
			'-loglevel',
			'error',
			'-i',
			url,
			'-c:a',
			'copy',
			'-f',
			container,
			`${folder}/hls.${container}`
		])

		let err: string

		ffmpegProc.stderr.on('data', function (data) {
			err = data.toString()
		})

		ffmpegProc.once('exit', function (code) {
			if (code == 0) resolve(fs.createReadStream(`${folder}/hls.${container}`))
			else reject(`FFMPEG HLS error: ${err}` || 'FFMPEG could not parse the HLS.')
		})
	})
}

export interface RawSearchResults {
	collection: (RawAlbum | RawTrack | RawArtist)[]
	total_results: number
	facets: []
	next_href: string
	query_urn: string
}

export interface ScClient {
	anonId: string
	version: string
	id: string | undefined
}
