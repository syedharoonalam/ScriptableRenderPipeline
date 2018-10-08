using System.Collections.Generic;
using UnityEditor;

namespace Data.Interfaces
{
    public interface IMayHaveErrors
    {
        bool hasErrors { get; }
        int errorCount { get; }

        IEnumerable<ShaderMessage> GetErrors();
        void AddError(ShaderMessage error);
        void AddErrors(IEnumerable<ShaderMessage> errors);
        void ClearErrors();
    }
}
