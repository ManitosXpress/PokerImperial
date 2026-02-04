
import os

# Suits paths (simplified vectors)
SPADE = "M100,50 C40,110 40,160 90,190 L90,210 L70,230 L130,230 L110,210 L110,190 C160,160 160,110 100,50 Z"
HEART = "M100,210 C40,150 40,70 100,70 C160,70 160,150 100,210 Z M50,70 A25,25 0 0,1 100,70 A25,25 0 0,1 150,70" 
# Better Heart path
HEART = "M100,200 C20,100 50,40 100,80 C150,40 180,100 100,200 Z"
DIAMOND = "M100,40 L160,135 L100,230 L40,135 Z"
CLUB = "M100,70 C70,70 70,110 90,120 C70,130 50,130 50,160 C50,190 90,190 95,170 L95,210 L70,230 L130,230 L110,210 L105,170 C110,190 150,190 150,160 C150,130 130,130 110,120 C130,110 130,70 100,70 Z"

# Colors
RED = "#D40000"
BLACK = "#000000"

SUITS = {
    's': {'path': SPADE, 'color': BLACK, 'name': 'spades'},
    'h': {'path': HEART, 'color': RED, 'name': 'hearts'},
    'd': {'path': DIAMOND, 'color': RED, 'name': 'diamonds'},
    'c': {'path': CLUB, 'color': BLACK, 'name': 'clubs'}
}

RANKS = ['2', '3', '4', '5', '6', '7', '8', '9', 't', 'j', 'q', 'k', 'a']
DISPLAY_RANKS = {
    '2': '2', '3': '3', '4': '4', '5': '5', '6': '6', '7': '7', '8': '8', '9': '9', 
    't': '10', 'j': 'J', 'q': 'Q', 'k': 'K', 'a': 'A'
}

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), '../assets/images/cards')
os.makedirs(OUTPUT_DIR, exist_ok=True)

def create_card_svg(rank_key, suit_key):
    suit = SUITS[suit_key]
    rank_disp = DISPLAY_RANKS[rank_key]
    color = suit['color']
    
    # Adjust font size for '10' so it fits
    font_size = "40" if rank_disp == "10" else "48"
    
    svg_content = f'''<svg width="200" height="300" viewBox="0 0 200 300" xmlns="http://www.w3.org/2000/svg">
    <!-- Card Base -->
    <rect x="2" y="2" width="196" height="296" rx="15" ry="15" fill="white" stroke="black" stroke-width="2"/>
    
    <!-- Top Left Corner -->
    <text x="20" y="50" font-family="Arial" font-size="{font_size}" font-weight="bold" fill="{color}" text-anchor="middle">{rank_disp}</text>
    <path d="{suit['path']}" transform="translate(-65, -30) scale(0.4)" fill="{color}"/>
    
    <!-- Bottom Right Corner (Rotated) -->
    <g transform="rotate(180, 100, 150)">
        <text x="20" y="50" font-family="Arial" font-size="{font_size}" font-weight="bold" fill="{color}" text-anchor="middle">{rank_disp}</text>
        <path d="{suit['path']}" transform="translate(-65, -30) scale(0.4)" fill="{color}"/>
    </g>
    
    <!-- Center Suit (Big) -->
    <path d="{suit['path']}" transform="translate(0, 15)" fill="{color}"/>
</svg>'''
    
    filename = f"{rank_key}{suit_key}.svg"
    with open(os.path.join(OUTPUT_DIR, filename), "w") as f:
        f.write(svg_content)
    print(f"Generated {filename}")

# Generate all 52 cards
for s_key in SUITS:
    for r_key in RANKS:
        create_card_svg(r_key, s_key)

# Generate Card Back
card_back_svg = '''<svg width="200" height="300" viewBox="0 0 200 300" xmlns="http://www.w3.org/2000/svg">
    <rect x="2" y="2" width="196" height="296" rx="15" ry="15" fill="#1A237E" stroke="gold" stroke-width="4"/>
    <pattern id="pattern" x="0" y="0" width="20" height="20" patternUnits="userSpaceOnUse">
        <circle cx="10" cy="10" r="5" fill="#283593" />
    </pattern>
    <rect x="10" y="10" width="180" height="280" rx="10" ry="10" fill="url(#pattern)" />
    <circle cx="100" cy="150" r="40" fill="gold" opacity="0.8"/>
    <text x="100" y="160" font-family="Arial" font-size="24" font-weight="bold" fill="#1A237E" text-anchor="middle">IMPERIAL</text>
</svg>'''

with open(os.path.join(OUTPUT_DIR, "card_back.svg"), "w") as f:
    f.write(card_back_svg)
print("Generated card_back.svg")

