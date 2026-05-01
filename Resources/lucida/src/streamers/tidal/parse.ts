import { Album, Artist, Playlist, Track } from '../../types.js'
import { DOMParser } from 'xmldom-qsa'

export interface RawArtist {
	id: string
	url?: string
	name: string
	picture?: string
}

export function parseArtist(raw: RawArtist): Artist {
	let picturePath

	if (raw?.picture != null) picturePath = raw?.picture?.replace(/-/gm, '/')
	else picturePath = null
	const artist: Artist = {
		id: raw.id,
		url: raw.url ?? `https://www.tidal.com/artist/${raw.id}`,
		name: raw.name
	}
	if (picturePath)
		artist.pictures = [
			`https://resources.tidal.com/images/${picturePath}/160x160.jpg`,
			`https://resources.tidal.com/images/${picturePath}/320x320.jpg`,
			`https://resources.tidal.com/images/${picturePath}/750x750.jpg`
		]
	return artist
}

export interface RawAlbum {
	cover: string
	id: number
	url: string
	numberOfTracks?: number
	numberOfVolumes?: number
	title: string
	artists?: RawArtist[]
	upc?: string
	releaseDate?: string
}

export function parseAlbum(raw: RawAlbum): Album {
	let coverPath

	if (raw.cover) coverPath = raw.cover.replace(/-/gm, '/')
	else coverPath = null

	const album: Album = {
		id: raw.id,
		url: raw.url ?? `https://tidal.com/browse/album/${raw.id}`,
		title: raw.title,
		coverArtwork: []
	}

	if (coverPath)
		album.coverArtwork = [
			{
				url: `https://resources.tidal.com/images/${coverPath}/160x160.jpg`,
				width: 160,
				height: 160
			},
			{
				url: `https://resources.tidal.com/images/${coverPath}/320x320.jpg`,
				width: 320,
				height: 320
			},
			{
				url: `https://resources.tidal.com/images/${coverPath}/1280x1280.jpg`,
				width: 1280,
				height: 1280
			}
		]
	if (raw.upc) album.upc = raw.upc
	if (raw.artists) album.artists = raw.artists.map(parseArtist)
	if (raw.numberOfTracks) album.trackCount = raw.numberOfTracks
	if (raw.numberOfVolumes) album.discCount = raw.numberOfVolumes
	if (raw.releaseDate) album.releaseDate = new Date(raw.releaseDate)
	return album
}

export interface RawPlaylist {
	uuid: string
	title: string
	url: string
	numberOfTracks: number
	tracks: Track[]
	cover: string
}

export function parsePlaylist(raw: RawPlaylist): Playlist {
	let coverPath

	if (raw.cover) coverPath = raw.cover.replace(/-/gm, '/')
	else coverPath = null

	const playlist: Playlist = {
		id: raw.uuid,
		title: raw.title,
		url: raw.url,
		trackCount: raw.numberOfTracks
	}

	playlist.coverArtwork = [
		{
			url: `https://resources.tidal.com/images/${coverPath}/160x160.jpg`,
			width: 160,
			height: 160
		},
		{
			url: `https://resources.tidal.com/images/${coverPath}/320x320.jpg`,
			width: 320,
			height: 320
		},
		{
			url: `https://resources.tidal.com/images/${coverPath}/1280x1280.jpg`,
			width: 1280,
			height: 1280
		}
	]

	return playlist
}

export interface RawTrack {
	url: string
	id: number
	artists: RawArtist[]
	duration: number
	copyright: string
	isrc?: string
	producers?: string[]
	composers?: string[]
	lyricists?: string[]
	explicit?: boolean
	trackNumber?: number
	volumeNumber?: number
	title: string
	version?: string
	album: RawAlbum
}

export function parseTrack(raw: RawTrack): Track {
	const track: Track = {
		url: raw.url,
		id: raw.id,
		title: raw.version ? `${raw.title} (${raw.version})` : raw.title,
		durationMs: raw.duration * 1000,
		artists: raw.artists.map(parseArtist),
		album: parseAlbum(raw.album)
	}
	if (raw.producers) track.producers = raw.producers
	if (raw.composers && raw.composers[0] != 'Not Documented') track.composers = raw.composers
	if (raw.lyricists) track.lyricists = raw.lyricists
	if (raw.isrc) track.isrc = raw.isrc
	if (raw.copyright) track.copyright = raw.copyright
	if (raw.explicit) track.explicit = raw.explicit
	if (raw.trackNumber) track.trackNumber = raw.trackNumber
	if (raw.volumeNumber) track.discNumber = raw.volumeNumber
	return track
}

export interface Contributor {
	name: string
	role: string
}

export interface ContributorsByType {
	type: string
	contributors: { name: string; id: number }[]
}

export function addCredits(raw: RawTrack, credits: Contributor[] | ContributorsByType[]): RawTrack {
	if (credits.length > 0 && 'type' in credits[0]) {
		credits = (<ContributorsByType[]>credits)
			.map((group) => {
				return group.contributors.map((contributor) => {
					return {
						name: contributor.name,
						role: group.type
					}
				})
			})
			.flat()
	}
	for (const contributor of <Contributor[]>credits) {
		switch (contributor.role) {
			case 'Producer':
				if (!raw.producers) raw.producers = []
				raw.producers.push(contributor.name)
				break
			case 'Composer':
				if (!raw.composers) raw.composers = []
				raw.composers.push(contributor.name)
				break
			case 'Lyricist':
				if (!raw.lyricists) raw.lyricists = []
				raw.lyricists.push(contributor.name)
				break
			default:
				break
		}
	}
	return raw
}

export function parseMpd(mpdString: string): string[] {
	const tracks: string[][] = []
	const { documentElement: doc } = new DOMParser().parseFromString(mpdString, 'application/xml')
	for (const adaptationSet of [...doc.querySelectorAll('AdaptationSet')]) {
		const contentType = adaptationSet.getAttribute('contentType')
		if (contentType != 'audio') throw new Error('Lucida only supports audio MPDs')
		for (const rep of [...doc.querySelectorAll('Representation')]) {
			let codec = rep.getAttribute('codecs')?.toLowerCase()
			if (codec?.startsWith('mp4a')) codec = 'aac'
			const segTemplate = rep.querySelector('SegmentTemplate')
			if (!segTemplate) throw new Error('No SegmentTemplate found')
			const initializationUrl = segTemplate.getAttribute('initialization')
			if (!initializationUrl) throw new Error('No initialization url')
			const mediaUrl = segTemplate.getAttribute('media')
			if (!mediaUrl) throw new Error('No media url')
			const trackUrls = [initializationUrl]
			const timeline = segTemplate.querySelector('SegmentTimeline')
			if (timeline) {
				let numSegments = 0
				// let currentTime = 0
				for (const s of [...timeline.querySelectorAll('S')]) {
					if (s.getAttribute('t')) {
						// currentTime = parseInt(<string>s.getAttribute('t'))
					}
					const r = parseInt(s.getAttribute('r') || '0') + 1
					if (!s.getAttribute('d')) throw new Error('No d property on SegmentTimeline')
					numSegments += r
					// for (let i = 0; i < r; i++) {
					// 	 currentTime += parseInt(<string>s.getAttribute('d'))
					// }
				}
				for (let i = 1; i <= numSegments; i++) {
					trackUrls.push(mediaUrl.replace('$Number$', i.toString()))
				}
			}
			tracks.push(trackUrls)
		}
	}
	return tracks[0]
}
