import Librespot, { LibrespotOptions } from 'librespot'
import {
	parseArtist,
	parseAlbum,
	parseTrack,
	parseEpisode,
	parsePodcast,
	parsePlaylist
} from './parse.js'
import {
	GetByUrlResponse,
	ItemType,
	SearchResults,
	StreamerAccount,
	StreamerWithLogin,
	Track
} from '../../types.js'

interface SpotifyOptions extends LibrespotOptions {
	username?: string
	storedCredential?: string
}

class Spotify implements StreamerWithLogin {
	client: Librespot
	hostnames = ['open.spotify.com']
	testData = {
		'https://open.spotify.com/track/1jzIJcHCXneHw7ojC6LXiF': {
			type: 'track',
			title: 'Potato Salad'
		},
		'https://open.spotify.com/album/5zi7WsKlIiUXv09tbGLKsE': {
			type: 'album',
			title: 'IGOR'
		},
		'https://open.spotify.com/artist/4V8LLVI7PbaPR0K2TGSxFF': {
			type: 'artist',
			title: 'Tyler, The Creator'
		}
	} as const

	username?: string
	storedCredential?: string

	constructor(options: SpotifyOptions) {
		this.client = new Librespot(options)

		const { username, storedCredential } = options
		this.username = username
		this.storedCredential = storedCredential
	}
	async login(username: string, password: string) {
		if (this.username && this.storedCredential)
			return await this.client.loginWithStoredCreds(this.username, this.storedCredential)
		else return await this.client.login(username, password)
	}
	getStoredCredentials() {
		return this.client.getStoredCredentials()
	}
	#getUrlParts(
		url: string
	): ['artist' | 'album' | 'track' | 'episode' | 'show' | 'playlist', string] {
		const urlObj = new URL(url)
		const parts = urlObj.pathname.slice(1).split('/')
		if (parts.length > 2) throw new Error('Unknown Spotify URL')
		if (
			parts[0] != 'artist' &&
			parts[0] != 'track' &&
			parts[0] != 'album' &&
			parts[0] != 'show' &&
			parts[0] != 'episode' &&
			parts[0] != 'playlist'
		) {
			throw new Error(`Spotify type "${parts[0]}" unsupported`)
		}
		if (!parts[1]) throw new Error('Unknown Spotify URL')
		return [parts[0], parts[1]]
	}
	async getTypeFromUrl(url: string) {
		let type: ItemType | 'show' = this.#getUrlParts(url)[0]

		if (type == 'show') type = 'podcast'

		return type
	}
	async getByUrl(url: string, limit = 0): Promise<GetByUrlResponse> {
		const [type, id] = this.#getUrlParts(url)
		switch (type) {
			case 'track': {
				const metadata = await this.client.get.trackMetadata(id)
				return {
					type,
					getStream: async () => {
						const streamData = await this.client.get.trackStream(id)
						return {
							mimeType: 'audio/ogg',
							sizeBytes: streamData.sizeBytes,
							stream: streamData.stream
						}
					},
					metadata: parseTrack(metadata)
				}
			}
			case 'artist': {
				const metadata = await this.client.get.artistMetadata(id)
				const albums = await this.client.get.artistAlbums(id, limit)
				return {
					type,
					metadata: {
						...parseArtist(metadata),
						albums: albums.map((e) => parseAlbum(e))
					}
				}
			}
			case 'album': {
				const metadata = await this.client.get.albumMetadata(id)
				const tracks = await this.client.get.albumTracks(id)
				if (tracks) {
					return {
						type,
						metadata: { ...parseAlbum(metadata), trackCount: tracks.length },
						tracks: tracks?.map((e) => parseTrack(e)) ?? []
					}
				}
				return {
					type,
					metadata: parseAlbum(metadata),
					tracks: []
				}
			}
			case 'episode': {
				const metadata = await this.client.get.episodeMetadata(id)
				return {
					type,
					getStream: async () => {
						const streamData = await this.client.get.episodeStream(id)
						return {
							mimeType: 'audio/ogg',
							sizeBytes: streamData.sizeBytes,
							stream: streamData.stream
						}
					},
					metadata: parseEpisode(metadata)
				}
			}
			case 'show': {
				const metadata = await this.client.get.podcastMetadata(id)
				return {
					type: 'podcast',
					metadata: parsePodcast(metadata),
					episodes: metadata.episodes?.map((e) => parseEpisode(e)) ?? []
				}
			}
			case 'playlist': {
				const metadata = await this.client.get.playlist(id)
				return {
					type: 'playlist',
					metadata: parsePlaylist(metadata),
					tracks: metadata.tracks?.map((e) => parseTrack(e)) ?? []
				}
			}
		}
	}
	async search(query: string): Promise<SearchResults> {
		const results = await this.client.browse.search(query)
		return {
			query,
			albums: results.albums?.map((e) => parseAlbum(e)) ?? [],
			artists: results.artists?.map((e) => parseArtist(e)) ?? [],
			tracks: results.tracks?.map((e) => parseTrack(e)) ?? []
		}
	}
	async isrcLookup(isrc: string): Promise<Track> {
		const results = await this.search(`isrc:${isrc}`)
		if (results?.tracks[0]) return <Track>(await this.getByUrl(results.tracks?.[0]?.url)).metadata
		else throw new Error(`Not available on Spotify.`)
	}
	async getAccountInfo(): Promise<StreamerAccount> {
		const info = await this.client.get.me()

		let premium
		if (info.plan == 'premium') premium = true
		else premium = false

		return {
			valid: true,
			premium,
			country: info.country,
			explicit: info.allowExplicit
		}
	}
}

export default Spotify
