module exciting;
import std::io;
import std::math;
import std::math::random;
import std::time;
import std::thread;

// ─── Terminal dimensions ───────────────────────────────────────
const int WIDTH  = 80;
const int HEIGHT = 30;
const int MAX_PARTICLES = 2048;

// ─── 2D Vector using built-in SIMD type ────────────────────────
alias Vec2 = float[<2>];

// ─── Particle types ────────────────────────────────────────────
enum ParticleKind : char
{
    ROCKET,
    SPARK,
    TRAIL,
    GLITTER,
}

// ─── Color codes for ANSI terminal ─────────────────────────────
enum Color : char
{
    RED,
    GREEN,
    YELLOW,
    BLUE,
    MAGENTA,
    CYAN,
    WHITE,
    BRIGHT_RED,
    BRIGHT_GREEN,
    BRIGHT_YELLOW,
}

fn String Color.ansi(self)
{
    switch (self)
    {
        case RED:            return "\x1b[31m";
        case GREEN:          return "\x1b[32m";
        case YELLOW:         return "\x1b[33m";
        case BLUE:           return "\x1b[34m";
        case MAGENTA:        return "\x1b[35m";
        case CYAN:           return "\x1b[36m";
        case WHITE:          return "\x1b[37m";
        case BRIGHT_RED:     return "\x1b[91m";
        case BRIGHT_GREEN:   return "\x1b[92m";
        case BRIGHT_YELLOW:  return "\x1b[93m";
    }
}

fn Color color_random()
{
    return (Color)((char)random::rand(10));
}

// ─── Particle struct ───────────────────────────────────────────
struct Particle
{
    Vec2         pos;
    Vec2         vel;
    float        life;
    float        max_life;
    ParticleKind kind;
    Color        color;
    char         symbol;
    bool         alive;
}

fn float Particle.life_ratio(&self)
{
    if (self.max_life == 0) return 0;
    return self.life / self.max_life;
}

fn void Particle.update(&self, float dt)
{
    if (!self.alive) return;

    self.pos = self.pos + self.vel * dt;

    // Gravity
    self.vel.y += 9.8f * dt;

    // Drag for sparks
    if (self.kind != ROCKET)
    {
        self.vel = self.vel * (1.0f - 0.5f * dt);
    }

    self.life -= dt;

    if (self.life <= 0)
    {
        self.alive = false;
        return;
    }

    // Fade symbol based on life
    float ratio = self.life_ratio();
    if (self.kind == SPARK || self.kind == GLITTER)
    {
        if (ratio > 0.7f)
        {
            self.symbol = '*';
        }
        else if (ratio > 0.4f)
        {
            self.symbol = '.';
        }
        else
        {
            self.symbol = '\'';
        }
    }
}

// ─── Firework explosion shapes ─────────────────────────────────
enum Shape : char
{
    CIRCLE,
    RING,
    STAR,
    DOUBLE,
    WILLOW,
}

fn Shape shape_random()
{
    return (Shape)((char)random::rand(5));
}

// ─── Fireworks system ──────────────────────────────────────────
struct Fireworks
{
    Particle[MAX_PARTICLES] particles;
    int          count;
    float        timer;
    float        next_launch;
    int          frame;
    char[WIDTH * HEIGHT] screen_buf;
    Color[WIDTH * HEIGHT] color_buf;
}

fn void Fireworks.init(&self)
{
    self.count = 0;
    self.timer = 0;
    self.next_launch = 0.5f;
    self.frame = 0;
}

fn Particle* Fireworks.add_particle(&self)
{
    // First try to find a dead slot
    for (int i = 0; i < self.count; i++)
    {
        if (!self.particles[i].alive)
        {
            return &self.particles[i];
        }
    }
    // Otherwise append
    if (self.count < MAX_PARTICLES)
    {
        Particle* p = &self.particles[self.count];
        self.count++;
        return p;
    }
    return null;
}

fn void Fireworks.launch_rocket(&self)
{
    Particle* p = self.add_particle();
    if (p == null) return;

    float x = (float)(10 + (int)random::rand(WIDTH - 20));
    *p = {
        .pos      = { x, (float)(HEIGHT - 1) },
        .vel      = { (float)((int)random::rand(5) - 2), -((float)(14 + (int)random::rand(8))) },
        .life     = 1.2f + (float)((int)random::rand(8)) * 0.1f,
        .max_life = 2.0f,
        .kind     = ROCKET,
        .color    = BRIGHT_YELLOW,
        .symbol   = '|',
        .alive    = true,
    };
}

fn void Fireworks.explode(&self, Vec2 pos, Color color, Shape shape)
{
    int count;
    switch (shape)
    {
        case CIRCLE: count = 36;
        case RING:   count = 28;
        case STAR:   count = 30;
        case DOUBLE: count = 44;
        case WILLOW: count = 40;
    }

    for (int i = 0; i < count; i++)
    {
        Particle* p = self.add_particle();
        if (p == null) return;

        float angle = (float)i / (float)count * 2.0f * (float)math::PI;
        float speed;

        switch (shape)
        {
            case CIRCLE:
                speed = 5.0f + (float)((int)random::rand(5));
            case RING:
                speed = 7.0f + (float)((int)random::rand(2));
            case STAR:
                speed = ((i % 6) < 3) ? 8.0f : 4.0f;
            case DOUBLE:
                speed = (i % 2 == 0) ? 6.0f : 3.0f;
                speed += (float)((int)random::rand(2));
            case WILLOW:
                speed = 3.0f + (float)((int)random::rand(4));
        }

        float vx = math::cos(angle) * speed;
        float vy = math::sin(angle) * speed;

        Color c = ((int)random::rand(4) == 0) ? color_random() : color;
        ParticleKind kind = ((int)random::rand(3) == 0) ? GLITTER : SPARK;

        *p = {
            .pos      = pos,
            .vel      = { vx, vy },
            .life     = 1.0f + (float)((int)random::rand(10)) * 0.1f,
            .max_life = 2.0f,
            .kind     = kind,
            .color    = c,
            .symbol   = '*',
            .alive    = true,
        };
    }
}

fn void Fireworks.update(&self, float dt)
{
    self.timer += dt;
    self.frame++;

    // Launch new rockets periodically
    if (self.timer >= self.next_launch)
    {
        int rockets = 1 + (int)random::rand(2);
        for (int r = 0; r < rockets; r++)
        {
            self.launch_rocket();
        }
        self.next_launch = self.timer + 0.3f + (float)((int)random::rand(12)) * 0.1f;
    }

    // Update particles and collect explosions
    Vec2[16]  explode_pos;
    Color[16] explode_color;
    Shape[16] explode_shape;
    int explode_count = 0;

    for (int i = 0; i < self.count; i++)
    {
        Particle* p = &self.particles[i];
        if (!p.alive) continue;

        p.update(dt);

        // Rocket reached apex -> explode
        if (p.kind == ROCKET && (p.vel.y >= 0 || !p.alive))
        {
            if (explode_count < 16)
            {
                explode_pos[explode_count]   = p.pos;
                explode_color[explode_count] = color_random();
                explode_shape[explode_count] = shape_random();
                explode_count++;
            }
            p.alive = false;
        }
    }

    // Perform explosions
    for (int e = 0; e < explode_count; e++)
    {
        self.explode(explode_pos[e], explode_color[e], explode_shape[e]);
    }
}

fn void Fireworks.render(&self)
{
    // Clear screen buffer
    for (int i = 0; i < WIDTH * HEIGHT; i++)
    {
        self.screen_buf[i] = ' ';
        self.color_buf[i]  = WHITE;
    }

    // Draw particles into buffer
    int alive_count = 0;
    for (int i = 0; i < self.count; i++)
    {
        Particle* p = &self.particles[i];
        if (!p.alive) continue;
        alive_count++;

        int px = (int)(p.pos.x + 0.5f);
        int py = (int)(p.pos.y + 0.5f);

        if (px >= 0 && px < WIDTH && py >= 0 && py < HEIGHT)
        {
            int idx = py * WIDTH + px;
            self.screen_buf[idx] = p.symbol;
            self.color_buf[idx]  = p.color;
        }
    }

    // Move cursor to top-left
    io::print("\x1b[H");

    // Draw top border
    io::print("\x1b[90m");
    io::print(".");
    for (int x = 0; x < WIDTH; x++) io::print("-");
    io::printn(".");

    // Render buffer to terminal with colors
    for (int y = 0; y < HEIGHT; y++)
    {
        io::print("\x1b[90m|");
        Color last_color = WHITE;
        for (int x = 0; x < WIDTH; x++)
        {
            int idx = y * WIDTH + x;
            char ch = self.screen_buf[idx];
            Color col = self.color_buf[idx];

            if (ch != ' ')
            {
                if (col != last_color)
                {
                    io::print(col.ansi());
                    last_color = col;
                }
                io::printf("%c", ch);
            }
            else
            {
                io::print(" ");
            }
        }
        io::print("\x1b[90m|");
        io::printn("");
    }

    // Draw bottom border with ground
    io::print("\x1b[32m");
    io::print("'");
    for (int x = 0; x < WIDTH; x++) io::print("~");
    io::printn("'");

    // Status line
    io::printf("\x1b[97m  Particles: %-6d  Frame: %-6d  [Ctrl+C to exit]\x1b[0m\n",
        alive_count, self.frame);
}

// ─── Entry point ───────────────────────────────────────────────
fn int main(String[] args)
{
    // Seed RNG
    random::srand((ulong)time::now());

    // Setup terminal
    io::print("\x1b[?25l");   // Hide cursor
    io::print("\x1b[2J");     // Clear screen

    Fireworks fw;
    fw.init();

    float dt = 0.05f;
    int max_frames = 300; // Run for ~15 seconds

    for (int f = 0; f < max_frames; f++)
    {
        fw.update(dt);
        fw.render();
        io::stdout().flush()!!;
        thread::sleep_ms(50);
    }

    // Grand finale: rapid fire!
    fw.next_launch = fw.timer; // Force immediate launches
    for (int i = 0; i < 10; i++)
    {
        fw.launch_rocket();
    }
    for (int f = 0; f < 80; f++)
    {
        if (f % 5 == 0)
        {
            fw.launch_rocket();
            fw.launch_rocket();
        }
        fw.update(dt);
        fw.render();
        io::stdout().flush()!!;
        thread::sleep_ms(50);
    }

    // Show cursor and reset
    io::print("\x1b[?25h\x1b[0m");
    io::printn("");
    io::printn("\x1b[93m  === Thanks for watching the fireworks! ===\x1b[0m");
    io::printn("");

    return 0;
}
