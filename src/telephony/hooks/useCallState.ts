import { useEffect, useState } from "react"

export function useCallState() {

  const [online, setOnline] = useState(navigator.onLine)

  useEffect(() => {

    function handleOnline() {
      setOnline(true)
    }

    function handleOffline() {
      setOnline(false)
    }

    window.addEventListener("online", handleOnline)
    window.addEventListener("offline", handleOffline)

    return () => {
      window.removeEventListener("online", handleOnline)
      window.removeEventListener("offline", handleOffline)
    }

  }, [])

  return { online }
}
