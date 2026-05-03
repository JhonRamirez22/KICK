const CLIENT_TOKEN = 'e1393935a959b4020a4491574f6490129f678acdaa92760471263db43487f823';

export default async function handler(req, res) {
  const { channel, count = 1 } = req.query;

  if (!channel) {
    return res.status(400).json({ error: 'Channel required' });
  }

  try {
    const tokens = [];
    
    for (let i = 0; i < parseInt(count); i++) {
      try {
        // Step 1: Session via channel page (exact Python logic)
        // Skip session - direct token attempt (matches Python single_token)
        const cookies = '';

        // Step 2: Token endpoint (chrome131 headers)
        const tokenRes = await fetch('https://websockets.kick.com/viewer/v1/token', {
          method: 'GET',
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
            'Accept': 'application/json, text/plain, */*',
            'Origin': 'https://kick.com',
            'Referer': `https://kick.com/${channel}`,
            'X-Client-Token': CLIENT_TOKEN,
            'X-Device-ID': crypto.randomUUID(),
            'X-Session-ID': crypto.randomUUID()
          }
        });

        const data = await tokenRes.json();
        const token = data.data?.token;
        
        if (token && token.length > 20) {
          tokens.push(token);
        }
      } catch (e) {
        console.error('Token fetch error:', e);
      }
      
      // Rate limiting
      await new Promise(r => setTimeout(r, 200));
    }

    return res.status(200).json({ tokens, count: tokens.length });
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
}
