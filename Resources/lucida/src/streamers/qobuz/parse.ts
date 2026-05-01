import { Artist, Album, Track, PlaylistGetByUrlResponse } from '../../types.js'

export interface RawArtist {
	id: number
	name: string
	picture?: string
	image?: {
		small: string
		medium: string
		large: string
	}
	albums?: {
		items: RawAlbum[]
	}
	tracks_appears_on?: {
		items: RawTrack[]
	}
}

export function parseArtist(raw: RawArtist): Artist {
	const artist: Artist = {
		id: raw.id.toString(),
		url: `https://play.qobuz.com/artist/${raw.id.toString()}`,
		name: raw.name
	}
	if (raw.picture) artist.pictures = [raw.picture]
	else if (raw.image) artist.pictures = [raw.image.small, raw.image.medium, raw.image.large]

	if (raw.albums) artist.albums = raw.albums.items.map(parseAlbum)
	if (raw.tracks_appears_on) artist.tracks = raw.tracks_appears_on.items.map(parseTrack)

	return artist
}

export interface RawAlbum {
	title: string
	version?: string
	id: string
	url: string
	image: {
		thumbnail: string
		small: string
		large: string
	}
	tracks?: {
		items: RawTrack[]
	}
	artists?: RawArtist[]
	artist: RawArtist
	upc: string
	released_at: number
	label?: {
		name: string
		id: number
	}
	genre?: {
		name: string
		id: number
		slug: string
	}
	copyright: string
}

export function parseAlbum(raw: RawAlbum) {
	const album: Album = {
		title: raw.version ? `${raw.title} (${raw.version})` : raw.title,
		id: raw.id,
		url: raw.url ?? `https://play.qobuz.com/album/${raw.id}`,
		coverArtwork: [
			{
				url: raw.image.thumbnail,
				width: 50,
				height: 50
			},
			{
				url: raw.image.small,
				width: 230,
				height: 230
			},
			{
				url: raw.image.large,
				width: 600,
				height: 600
			}
		],
		artists: raw.artists?.map(parseArtist) ?? [parseArtist(raw.artist)],
		upc: raw.upc,
		releaseDate: new Date(raw.released_at * 1000),
		copyright: raw.copyright
	}

	if (raw.label?.name) album.label = raw.label.name
	if (raw.genre?.name) album.genre = [raw.genre.name]

	return album
}

export interface RawTrack {
	title: string
	version?: string
	id: number
	copyright?: string
	performer: RawArtist
	album?: RawAlbum
	track_number?: number
	media_number?: number
	duration: number
	parental_warning: boolean
	isrc: string
	performers?: string
}

export function parseTrack(raw: RawTrack): Track {
	const artists = []
	const artist = raw.performer ?? raw.album?.artist
	if (artist) artists.push(parseArtist(artist))

	let track: Track = {
		title: raw.version ? `${raw.title} (${raw.version})` : raw.title,
		id: raw.id.toString(),
		url: `https://play.qobuz.com/track/${raw.id.toString()}`,
		copyright: raw.copyright,
		artists,
		durationMs: raw.duration * 1000,
		explicit: raw.parental_warning,
		isrc: raw.isrc,
		genres: []
	}
	if (raw.album) track.album = parseAlbum(raw.album)
	if (raw.track_number) track.trackNumber = raw.track_number
	if (raw.media_number) track.discNumber = raw.media_number
	if (raw.performers) track = parsePerformers(raw.performers, track)
	return track
}

function parsePerformers(performers: string, track: Track) {
	const pre = performers.split(' - ')
	track.producers = []
	track.composers = []
	track.lyricists = []
	track.performers = []
	track.engineers = []

	for (const i in pre) {
		const name = pre[i].split(', ')[0]
		const credits = pre[i].split(', ').slice(1).join(', ')

		if (credits.toLowerCase().includes('producer')) track.producers.push(name)
		if (credits.toLowerCase().includes('lyricist')) track.lyricists.push(name)
		if (credits.toLowerCase().includes('composer')) track.composers.push(name)
		if (
			credits.toLowerCase().includes('performer') ||
			credits.toLowerCase().includes('featuredartist')
		)
			track.performers.push(name)
		if (credits.toLowerCase().includes('engineer')) track.engineers.push(name)
	}

	return track
}

export interface RawPlaylist {
	owner: {
		id: number
		name: string
	}
	id: number
	name: string
	images: string[]
	is_collaborative: boolean
	description: string
	created_at: number
	duration: number
	tracks_count: number
	tracks: {
		offset?: number
		limit?: number
		total?: number
		items: RawTrack[]
	}
}

export function parsePlaylist(raw: RawPlaylist) {
	return <PlaylistGetByUrlResponse>{
		type: 'playlist',
		metadata: {
			id: raw.id,
			title: raw.name,
			trackCount: raw?.tracks_count || raw?.tracks?.total,
			url: `https://open.qobuz.com/playlist/${raw.id}`
		},
		tracks: raw.tracks?.items.map(parseTrack)
	}
}
