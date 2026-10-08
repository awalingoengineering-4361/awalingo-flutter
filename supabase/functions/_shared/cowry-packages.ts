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

// Mirrors the registered provider adapters' static metadata
// (flutterwave.ts/paystack.ts: id/supportedCurrencies/minimumAmounts).
export type CowryPaymentProvider = "FLUTTERWAVE" | "PAYSTACK";

export const PROVIDER_DEFINITIONS: Record<
  CowryPaymentProvider,
  { supportedCurrencies: string[]; minimumAmounts: Record<string, number> }
> = {
  FLUTTERWAVE: { supportedCurrencies: ["NGN"], minimumAmounts: { NGN: 0.01 } },
  PAYSTACK: {
    supportedCurrencies: ["NGN", "USD"],
    minimumAmounts: { NGN: 50.0, USD: 2.0 },
  },
};
