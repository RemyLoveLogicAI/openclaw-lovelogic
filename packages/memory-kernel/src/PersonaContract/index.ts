export interface PersonaContract {
  id: string;
  ownerId: string;
  policies: string[];
  createdAt: Date;
}

export async function createPersona(ownerId: string): Promise<PersonaContract> {
  // Skeleton implementation
  return { id: 'temp-id', ownerId, policies: [], createdAt: new Date() };
}
