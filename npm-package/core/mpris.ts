import call from "./call";

export interface Metadata {
    trackid?: string;
    length?: number;
    artUrl?: string;
    album?: string;
    albumArtist?: string[];
    artist?: string[];
    asText?: string;
    audioBPM?: number;
    autoRating?: number;
    comment?: string[];
    composer?: string[];
    contentCreated?: string;
    discNumber?: number;
    firstUsed?: string;
    genre?: string[];
    lastUsed?: string;
    lyricist?: string[];
    title?: string;
    trackNumber?: number;
    url?: string;
    useCount?: number;
    userRating?: number;
}

export interface PlayerInfo {
    busName: string;
    identity?: string;
    desktopEntry?: string;
    canQuit: boolean;
    canRaise: boolean;
    canSetFullscreen: boolean;
    hasTrackList: boolean;
    fullscreen: boolean;
}

export interface PlayerStatus {
    canControl: boolean;
    canGoNext: boolean;
    canGoPrevious: boolean;
    canPause: boolean;
    canPlay: boolean;
    canSeek: boolean;
    loopStatus: "None" | "Track" | "Playlist";
    maximumRate: number;
    metadata?: Metadata;
    minimumRate: number;
    playbackStatus: "Playing" | "Paused" | "Stopped";
    position: number;
    rate: number;
    shuffle: boolean;
    volume: number;
}

/**
 * MPRIS Media Player class
 * Represents a single media player with capability checking
 */
export class Player {
    public readonly busName: string;
    public identity?: string;
    public desktopEntry?: string;

    // Capabilities
    public canQuit: boolean = false;
    public canRaise: boolean = false;
    public canSetFullscreen: boolean = false;
    public hasTrackList: boolean = false;
    public canControl: boolean = false;
    public canGoNext: boolean = false;
    public canGoPrevious: boolean = false;
    public canPlay: boolean = false;
    public canPause: boolean = false;
    public canSeek: boolean = false;

    private constructor(busName: string) {
        this.busName = busName;
    }

    /**
     * Create and initialize a Player instance
     * Fetches player capabilities on initialization
     */
    static async create(busName: string): Promise<Player> {
        const player = new Player(busName);
        await player.fetchCapabilities();
        return player;
    }

    /**
     * Fetch player capabilities and info
     */
    private async fetchCapabilities(): Promise<void> {
        try {
            const info: PlayerInfo = await call("mpris.getPlayerInfo", this.busName);
            this.identity = info.identity;
            this.desktopEntry = info.desktopEntry;
            this.canQuit = info.canQuit;
            this.canRaise = info.canRaise;
            this.canSetFullscreen = info.canSetFullscreen;
            this.hasTrackList = info.hasTrackList;

            const status: PlayerStatus = await call("mpris.getPlayerStatus", this.busName);
            this.canControl = status.canControl;
            this.canGoNext = status.canGoNext;
            this.canGoPrevious = status.canGoPrevious;
            this.canPlay = status.canPlay;
            this.canPause = status.canPause;
            this.canSeek = status.canSeek;
        } catch (error) {
            console.error(`Failed to fetch capabilities for ${this.busName}:`, error);
        }
    }

    /**
     * Brings the media player to the front
     */
    async raise(): Promise<void> {
        if (!this.canRaise) {
            throw new Error(`Player ${this.busName} does not support raise`);
        }
        return call("mpris.raise", this.busName);
    }

    /**
     * Quit the media player
     */
    async quit(): Promise<void> {
        if (!this.canQuit) {
            throw new Error(`Player ${this.busName} does not support quit`);
        }
        return call("mpris.quit", this.busName);
    }

    /**
     * Skip to the next track
     */
    async next(): Promise<void> {
        if (!this.canGoNext) {
            throw new Error(`Player ${this.busName} does not support next`);
        }
        return call("mpris.next", this.busName);
    }

    /**
     * Skip to the previous track
     */
    async previous(): Promise<void> {
        if (!this.canGoPrevious) {
            throw new Error(`Player ${this.busName} does not support previous`);
        }
        return call("mpris.previous", this.busName);
    }

    /**
     * Pause playback
     */
    async pause(): Promise<void> {
        if (!this.canPause) {
            throw new Error(`Player ${this.busName} does not support pause`);
        }
        return call("mpris.pause", this.busName);
    }

    /**
     * Toggle between play and pause
     */
    async playPause(): Promise<void> {
        if (!this.canControl) {
            throw new Error(`Player ${this.busName} cannot be controlled`);
        }
        return call("mpris.playPause", this.busName);
    }

    /**
     * Stop playback
     */
    async stop(): Promise<void> {
        if (!this.canControl) {
            throw new Error(`Player ${this.busName} cannot be controlled`);
        }
        return call("mpris.stop", this.busName);
    }

    /**
     * Start or resume playback
     */
    async play(): Promise<void> {
        if (!this.canPlay) {
            throw new Error(`Player ${this.busName} does not support play`);
        }
        return call("mpris.play", this.busName);
    }

    /**
     * Seek forward or backward
     * @param offset - The offset in microseconds
     */
    async seek(offset: number): Promise<void> {
        if (!this.canSeek) {
            throw new Error(`Player ${this.busName} does not support seek`);
        }
        return call("mpris.seek", this.busName, offset);
    }

    /**
     * Set the current track position
     * @param trackId - The track ID
     * @param position - The position in microseconds
     */
    async setPosition(trackId: string, position: number): Promise<void> {
        if (!this.canSeek) {
            throw new Error(`Player ${this.busName} does not support seek`);
        }
        return call("mpris.setPosition", this.busName, trackId, position);
    }

    /**
     * Open a URI in the media player
     */
    async openUri(uri: string): Promise<void> {
        if (!this.canControl) {
            throw new Error(`Player ${this.busName} cannot be controlled`);
        }
        return call("mpris.openUri", this.busName, uri);
    }

    /**
     * Get fullscreen status
     */
    async getFullscreen(): Promise<boolean> {
        return call("mpris.getFullscreen", this.busName);
    }

    /**
     * Set fullscreen status
     */
    async setFullscreen(value: boolean): Promise<void> {
        if (!this.canSetFullscreen) {
            throw new Error(`Player ${this.busName} does not support fullscreen`);
        }
        return call("mpris.setFullscreen", this.busName, value);
    }

    /**
     * Get playback status
     */
    async getPlaybackStatus(): Promise<"Playing" | "Paused" | "Stopped"> {
        return call("mpris.getPlaybackStatus", this.busName);
    }

    /**
     * Get loop status
     */
    async getLoopStatus(): Promise<"None" | "Track" | "Playlist"> {
        return call("mpris.getLoopStatus", this.busName);
    }

    /**
     * Set loop status
     */
    async setLoopStatus(status: "None" | "Track" | "Playlist"): Promise<void> {
        if (!this.canControl) {
            throw new Error(`Player ${this.busName} cannot be controlled`);
        }
        return call("mpris.setLoopStatus", this.busName, status);
    }

    /**
     * Get playback rate
     */
    async getRate(): Promise<number> {
        return call("mpris.getRate", this.busName);
    }

    /**
     * Set playback rate
     */
    async setRate(rate: number): Promise<void> {
        if (!this.canControl) {
            throw new Error(`Player ${this.busName} cannot be controlled`);
        }
        return call("mpris.setRate", this.busName, rate);
    }

    /**
     * Get shuffle status
     */
    async getShuffle(): Promise<boolean> {
        return call("mpris.getShuffle", this.busName);
    }

    /**
     * Set shuffle status
     */
    async setShuffle(shuffle: boolean): Promise<void> {
        if (!this.canControl) {
            throw new Error(`Player ${this.busName} cannot be controlled`);
        }
        return call("mpris.setShuffle", this.busName, shuffle);
    }

    /**
     * Get volume (0.0 to 1.0)
     */
    async getVolume(): Promise<number> {
        if (!this.canControl) {
            throw new Error(`Player ${this.busName} cannot be controlled`);
        }
        return call("mpris.getVolume", this.busName);
    }

    /**
     * Set volume (0.0 to 1.0)
     */
    async setVolume(volume: number): Promise<void> {
        if (!this.canControl) {
            throw new Error(`Player ${this.busName} cannot be controlled`);
        }
        return call("mpris.setVolume", this.busName, volume);
    }

    /**
     * Get current position in microseconds
     */
    async getPosition(): Promise<number> {
        return call("mpris.getPosition", this.busName);
    }

    /**
     * Get minimum playback rate
     */
    async getMinimumRate(): Promise<number> {
        return call("mpris.getMinimumRate", this.busName);
    }

    /**
     * Get maximum playback rate
     */
    async getMaximumRate(): Promise<number> {
        return call("mpris.getMaximumRate", this.busName);
    }

    /**
     * Get the metadata of the current track
     */
    async getMetadata(): Promise<Metadata> {
        return call("mpris.getMetadata", this.busName);
    }

    /**
     * Get player information
     */
    async getPlayerInfo(): Promise<PlayerInfo> {
        return call("mpris.getPlayerInfo", this.busName);
    }

    /**
     * Get player status including playback state and metadata
     */
    async getPlayerStatus(): Promise<PlayerStatus> {
        return call("mpris.getPlayerStatus", this.busName);
    }

    /**
     * Refresh player capabilities
     * Useful if player state might have changed
     */
    async refresh(): Promise<void> {
        await this.fetchCapabilities();
    }
}

/**
 * List all available MPRIS media players as Player instances
 */
export async function list(): Promise<Player[]> {
    const busNames: string[] = await call("mpris.listPlayers");
    const players = await Promise.all(busNames.map((busName) => Player.create(busName)));
    return players;
}
