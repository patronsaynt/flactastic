import Spotify from './../build/streamers/spotify/main.js'

const client = new Spotify({ clientId: '9a8d2f0ce77a4e248bb71fefcb557637' })
await client.login(process.env.SPOTIFY_USERNAME, process.env.SPOTIFY_PASSWORD)

const storedCreds = client.getStoredCredentials()
console.log('[spotify] New config:', storedCreds)
