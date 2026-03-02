
type VoicemailPlayerProps = {
  voicemailUrl: string;
  authToken?: string;
};

export function VoicemailPlayer({ voicemailUrl, authToken }: VoicemailPlayerProps) {
  const sourceUrl = authToken
    ? `${voicemailUrl}${voicemailUrl.includes("?") ? "&" : "?"}token=${encodeURIComponent(authToken)}`
    : voicemailUrl;

  return (
    <audio
      controls
      preload="none"
    >
      <source src={sourceUrl} type="audio/mpeg" />
    </audio>
  );
}
