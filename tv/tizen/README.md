# Samsung Tizen TV package source

This is the Deeprowss Samsung TV web-app project, branded with the original Deeprowss logo. It opens the hosted receiver at `https://deeprows.github.io/myflutter-app/`.

## Build a signed WGT

1. Install Samsung Tizen Studio and the TV extension on Windows.
2. Open this `tv/tizen` folder as a Tizen Web Application project.
3. In Tizen Certificate Manager, create/select a Samsung TV certificate profile. The author certificate and distributor certificate must be valid for the target TV and signing level.
4. Select the TV profile and build/package the project as a `.wgt` from Tizen Studio (or `tizen package -t wgt -s <your-profile>` with the Tizen CLI).
5. Install for development using the Samsung TV Developer Mode / SDB workflow. Public distribution requires Samsung Seller Office review.

A valid Samsung signing profile is required. The source project is supplied here; an unsigned ZIP is deliberately not labelled as an installable WGT.
