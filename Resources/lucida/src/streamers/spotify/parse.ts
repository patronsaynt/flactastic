import type {
	SpotifyAlbum,
	SpotifyArtist,
	SpotifyThumbnail,
	SpotifyTrack,
	SpotifyEpisode,
	SpotifyPodcast,
	SpotifyPlaylist
} from 'librespot/types'
import { Album, Artist, Episode, Playlist, Podcast, Track } from '../../types.js'

function parseThumbnails(raw: SpotifyThumbnail[]) {
	return raw
		.sort((a, b) => (a.width ?? 0) - (b.width ?? 0))
		.map((e) => {
			return {
				width: e.width ?? 0,
				height: e.height ?? 0,
				url: e.url
			}
		})
}

export function parseArtist(raw: SpotifyArtist) {
	const artist: Artist = {
		id: raw.id,
		url: raw.externalUrl,
		name: raw.name
	}
	if (raw.avatar) artist.pictures = parseThumbnails(raw.avatar).map((e) => e.url)
	if (raw.albums) artist.albums = raw.albums.map((e) => parseAlbum(e))
	return artist
}

export function parseTrack(raw: SpotifyTrack) {
	const track: Track = {
		title: raw.name,
		id: raw.id,
		url: raw.externalUrl,
		explicit: raw.explicit,
		trackNumber: raw.trackNumber,
		discNumber: raw.discNumber,
		artists: raw.artists?.map((e) => parseArtist(e)) ?? [],
		durationMs: raw.durationMs
	}
	if (raw.album) track.album = parseAlbum(raw.album)
	if (raw?.isrc) track.isrc = raw.isrc
	if (raw?.album?.availableMarkets) track.regions = raw.album.availableMarkets
	return track
}

export function parseAlbum(raw: SpotifyAlbum) {
	const album: Album = {
		title: raw.name,
		id: raw.id,
		url: raw.externalUrl,
		trackCount: raw.totalTracks,
		releaseDate: raw.releaseDate,
		coverArtwork: parseThumbnails(raw.coverArtwork),
		artists: raw.artists.map((e) => parseArtist(e))
	}

	if (raw.availableMarkets) album.regions = raw.availableMarkets

	return album
}

export function parseEpisode(raw: SpotifyEpisode) {
	const episode: Episode = {
		title: raw.name,
		id: raw.id,
		url: raw.externalUrl,
		explicit: raw.explicit,
		description: raw.description,
		coverArtwork: parseThumbnails(raw.coverArtwork),
		releaseDate: raw.releaseDate,
		durationMs: raw.durationMs
	}
	if (raw.podcast) episode.podcast = parsePodcast(raw.podcast)
	return episode
}

export function parsePodcast(raw: SpotifyPodcast) {
	const podcast: Podcast = {
		title: raw.name,
		id: raw.id,
		url: raw.externalUrl,
		description: raw.description,
		coverArtwork: parseThumbnails(raw.coverArtwork)
	}
	if (typeof raw.explicit == 'boolean') podcast.explicit = raw.explicit
	if (raw.episodes) podcast.episodes = raw.episodes.map((e) => parseEpisode(e))

	return podcast
}

export function parsePlaylist(raw: SpotifyPlaylist) {
	const playlist: Playlist = {
		id: raw.id,
		title: raw.name,
		url: raw.externalUrl,
		trackCount: raw.totalTracks,
		coverArtwork: parseThumbnails(raw.coverArtwork)
	}

	return playlist
}
