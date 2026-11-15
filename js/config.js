// Site configuration.
//
// The Cesium ion token is used in the browser, so it is visible to anyone who
// opens the site. Restrict it to your GitHub Pages URL in the Cesium ion
// dashboard (Access Tokens → Allowed URLs).
export const CONFIG = {
  cesiumIonToken:
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJub25jZSI6IlNZSmJIZHZWZjFjbFlnd3oiLCJqdGkiOiI1Yzg3ZDhjYy1iZDQwLTRhMDYtYjEzYS04MWIwMzQ3YjIzNmMiLCJpZCI6NTQ5NjY5LCJpc3MiOiJodHRwczovL2FwaS5jZXNpdW0uY29tIiwiYXVkIjoidW5kZWZpbmVkX2RlZmF1bHQiLCJpYXQiOjE3OTQ3MDI0MTd9.BUaAC7DkdbyIsCAgaozzDtshPpwt_hBLtnDQBx-rxAA",

  // Cesium ion asset ID of the "Cesium Mars" 3D Tiles dataset. Add it to your ion
  // account from the Asset Depot and check the ID there. If it fails to load,
  // the site falls back to a procedurally textured Mars globe.
  marsIonAssetId: 3644333,

  // Location images (js/photos.js). Both are used in the browser, so restrict
  // them to your GitHub Pages URL: the Google key under "Application
  // restrictions → Websites" with the Street View Static API and Maps
  // JavaScript API enabled. Leave a value empty to skip that source.
  googleMapsKey: "AIzaSyCLHq6lXs6hw9P6YHcIokxMZC_wY-cA1GU",
  mapillaryToken: "",

  // Earth score map
  barMaxHeightMeters: 1_400_000,
  barMinHeightMeters: 30_000,
  barWidthMeters: 115_000,
};
