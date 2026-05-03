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
        const sessionRes = await fetch(`https://kick.com/${channel}`, {
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9',
            'Accept-Encoding': 'gzip, deflate, br',
            'Sec-Ch-Ua': '"Google Chrome";v="131", "Chromium";v="131", "Not_A Brand";v="24"',
            'Sec-Ch-Ua-Mobile': '?0',
            'Sec-Ch-Ua-Platform': '"Windows"',
            'Sec-Fetch-Dest': 'document',
            'Sec-Fetch-Mode': 'navigate',
            'Sec-Fetch-Site': 'none',
            'Sec-Fetch-User': '?1',
            'Upgrade-Insecure-Requests': '1'
          }
        });

        const cookies = sessionRes.headers.get('set-cookie') || '';

        // Step 2: Token endpoint (chrome131 headers)
        const tokenRes = await fetch('https://websockets.kick.com/viewer/v1/token', {
          method: 'GET',
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'en-US,en;q=0.5',
            'Accept-Encoding': 'gzip, deflate, br',
            'Sec-Ch-Ua': '"Google Chrome";v="131", "Chromium";v="131", "Not_A Brand";v="24"',
            'Sec-Ch-Ua-Mobile': '?0',
            'Sec-Ch-Ua-Platform': '"Windows"',
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'same-site',
            'Origin': 'https://kick.com',
            'Referer': `https://kick.com/${channel}`,
            'X-Client-Token': CLIENT_TOKEN,
            'X-Device-ID': crypto.randomUUID(),
            'X-Session-ID': crypto.randomUUID(),
            'Cookie': cookies
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
