// Mirrors COWRY_PACKAGE_DEFINITIONS (neolingo: src/lib/cowry-payments.ts).
// The package catalog (id/name/cowries) is a fixed list, not DB-driven;
// only the price per currency (cowry_package_prices) is.
export interface CowryPackageDefinition {
  id: string;
  name: string;
  cowries: number;
}

export const COWRY_PACKAGE_DEFINITIONS: CowryPackageDefinition[] = [
  { id: "copper-50", name: "Copper", cowries: 50 },
  { id: "silver-100", name: "Silver", cowries: 100 },
  { id: "gold-500", name: "Gold", cowries: 500 },
  { id: "diamond-1000", name: "Diamond", cowries: 1000 },
];

export function findCowryPackageDefinition(
  packageId: string,
): CowryPackageDefinition | undefined {
  return COWRY_PACKAGE_DEFINITIONS.find((pkg) => pkg.id === packageId);
}

// Mirrors the registered provider adapter's static metadata
// (paystack.ts: id/supportedCurrencies/minimumAmounts). Paystack is the only
// payment provider.
export type CowryPaymentProvider = "PAYSTACK";

export const PROVIDER_DEFINITIONS: Record<
  CowryPaymentProvider,
  { supportedCurrencies: string[]; minimumAmounts: Record<string, number> }
> = {
  PAYSTACK: {
    supportedCurrencies: ["NGN", "USD"],
    minimumAmounts: { NGN: 50.0, USD: 2.0 },
  },
};

// In-app purchase products for the iOS and Android builds. Apple and Google
// require their own billing for virtual currency, so the store apps sell
// cowries through these consumable products instead of Paystack. The same
// ids must be created in App Store Connect and the Play Console.
export type StorePaymentProvider = "APP_STORE" | "GOOGLE_PLAY";

export const STORE_PRODUCT_IDS: Record<string, string> = {
  "copper-50": "cowries_copper_50",
  "silver-100": "cowries_silver_100",
  "gold-500": "cowries_gold_500",
  "diamond-1000": "cowries_diamond_1000",
};

export function findCowryPackageByStoreProductId(
  productId: string,
): CowryPackageDefinition | undefined {
  const packageId = Object.keys(STORE_PRODUCT_IDS).find(
    (id) => STORE_PRODUCT_IDS[id] === productId,
  );
  return packageId ? findCowryPackageDefinition(packageId) : undefined;
}
