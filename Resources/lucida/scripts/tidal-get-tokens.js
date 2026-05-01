import Tidal from './../build/streamers/tidal/main.js'

const client = new Tidal({
	tvToken: process.env.TV_TOKEN,
	tvSecret: process.env.TV_SECRET
})
client.getTokens()
